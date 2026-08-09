package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.SignatureValidator;
import digital.slovensko.autogram.util.DSSUtils;
import eu.europa.esig.dss.asic.cades.extract.ASiCWithCAdESContainerExtractor;
import eu.europa.esig.dss.asic.cades.validation.ASiCContainerWithCAdESValidator;
import eu.europa.esig.dss.asic.xades.extract.ASiCWithXAdESContainerExtractor;
import eu.europa.esig.dss.asic.xades.validation.ASiCContainerWithXAdESValidator;
import eu.europa.esig.dss.model.DSSDocument;
import eu.europa.esig.dss.model.FileDocument;
import eu.europa.esig.dss.model.InMemoryDocument;
import eu.europa.esig.dss.simplereport.SimpleReport;
import eu.europa.esig.dss.validation.SignedDocumentValidator;

import java.nio.file.Path;
import java.time.Instant;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

public final class MachineInspectionService {
    private final ReportReader reportReader;
    private final ByteReportReader byteReportReader;
    private final TimestampQualificationEvaluator timestampQualificationEvaluator;
    private final boolean genericPathInspection;
    private final ValidatorReportReader validatorReportReader;

    public MachineInspectionService() {
        reportReader = null;
        byteReportReader = null;
        timestampQualificationEvaluator = new TimestampQualificationEvaluator();
        genericPathInspection = true;
        validatorReportReader = MachineInspectionService::readTrustedReport;
    }

    MachineInspectionService(ReportReader reportReader) {
        this(reportReader, content -> readTrustedReport(documentValidator(new InMemoryDocument(content))));
    }

    MachineInspectionService(ReportReader reportReader, ByteReportReader byteReportReader) {
        this.reportReader = reportReader;
        this.byteReportReader = byteReportReader;
        timestampQualificationEvaluator = new TimestampQualificationEvaluator();
        genericPathInspection = false;
        validatorReportReader = null;
    }

    static MachineInspectionService withValidatorReportReader(ValidatorReportReader validatorReportReader) {
        return new MachineInspectionService(validatorReportReader, true);
    }

    private MachineInspectionService(ValidatorReportReader validatorReportReader, boolean genericPathInspection) {
        reportReader = null;
        byteReportReader = null;
        timestampQualificationEvaluator = new TimestampQualificationEvaluator();
        this.genericPathInspection = genericPathInspection;
        this.validatorReportReader = validatorReportReader;
    }

    public JsonObject inspect(Path path) {
        if (genericPathInspection) {
            return mapAsicInspection(readTrustedInspection(path));
        }
        return mapReport(reportReader.read(path));
    }

    public JsonObject inspect(byte[] content) {
        if (genericPathInspection) {
            return mapReport(validatorReportReader.read(documentValidator(new InMemoryDocument(content))));
        }
        return mapReport(byteReportReader.read(content));
    }

    static int readStructuralSignatureCount(Path path) {
        return documentValidator(new FileDocument(path.toFile())).getSignatures().size();
    }

    private static SimpleReport readTrustedReport(SignedDocumentValidator validator) {
        return SignatureValidator.getInstance().validate(validator).getSimpleReport();
    }

    private AsicInspection readTrustedInspection(Path path) {
        DSSDocument document = new FileDocument(path.toFile());
        var validator = documentValidator(document);
        var report = validatorReportReader.read(validator);
        if (!isAsic(validator)) {
            return new AsicInspection(report, null, Map.of());
        }

        var documents = asicDocuments(document, validator);
        var coverage = new LinkedHashMap<String, List<String>>();
        for (var signatureId : report.getSignatureIdList()) {
            coverage.put(signatureId, documentNames(validator.getOriginalDocuments(signatureId)));
        }
        return new AsicInspection(report, documents, coverage);
    }

    private static SignedDocumentValidator documentValidator(DSSDocument document) {
        var validator = DSSUtils.createDocumentValidator(document);
        if (validator == null) {
            throw new IllegalArgumentException("Unsupported document");
        }
        return validator;
    }

    private static boolean isAsic(SignedDocumentValidator validator) {
        return validator instanceof ASiCContainerWithXAdESValidator || validator instanceof ASiCContainerWithCAdESValidator;
    }

    private static List<String> asicDocuments(DSSDocument document, SignedDocumentValidator validator) {
        if (validator instanceof ASiCContainerWithXAdESValidator) {
            return documentNames(new ASiCWithXAdESContainerExtractor(document).extract().getSignedDocuments());
        }
        return documentNames(new ASiCWithCAdESContainerExtractor(document).extract().getSignedDocuments());
    }

    private static List<String> documentNames(List<DSSDocument> documents) {
        var names = new LinkedHashSet<String>();
        for (var document : documents) {
            if (document.getName() != null) {
                names.add(document.getName());
            }
        }
        return List.copyOf(names);
    }

    private JsonObject mapReport(SimpleReport report) {
        return mapAsicInspection(new AsicInspection(report, null, Map.of()));
    }

    private JsonObject mapAsicInspection(AsicInspection inspection) {
        var payload = new JsonObject();
        var signatures = new com.google.gson.JsonArray();
        for (var signatureId : inspection.report().getSignatureIdList()) {
            signatures.add(mapSignature(inspection.report(), signatureId,
                    inspection.coverage().getOrDefault(signatureId, List.of())));
        }
        payload.add("signatures", signatures);
        if (inspection.documents() != null) {
            var documents = new com.google.gson.JsonArray();
            for (var name : inspection.documents()) {
                var document = new JsonObject();
                document.addProperty("name", name);
                documents.add(document);
            }
            payload.add("documents", documents);
        }
        return payload;
    }

    private JsonObject mapSignature(SimpleReport report, String signatureId, List<String> coveredDocuments) {
        var signature = new JsonObject();
        addString(signature, "id", signatureId);
        addEnum(signature, "format", report.getSignatureFormat(signatureId));
        addString(signature, "signerDisplayName", report.getSignedBy(signatureId));
        addEnum(signature, "signerCertificateQualification", report.getSignatureQualification(signatureId));
        addDate(signature, "signingTime", report.getSigningTime(signatureId));
        signature.addProperty("valid", report.isValid(signatureId));
        addEnum(signature, "indication", report.getIndication(signatureId));
        signature.addProperty("qualifiedTimestampValid",
                timestampQualificationEvaluator.hasValidQualifiedTimestamp(report, signatureId));

        var timestamps = new com.google.gson.JsonArray();
        for (var timestamp : report.getSignatureTimestamps(signatureId)) {
            timestamps.add(mapTimestamp(report, timestamp.getId()));
        }
        signature.add("timestamps", timestamps);
        if (!coveredDocuments.isEmpty()) {
            var documents = new com.google.gson.JsonArray();
            for (var name : coveredDocuments) {
                documents.add(name);
            }
            signature.add("documents", documents);
        }
        return signature;
    }

    private static JsonObject mapTimestamp(SimpleReport report, String timestampId) {
        var timestamp = new JsonObject();
        addString(timestamp, "id", timestampId);
        addDate(timestamp, "productionTime", report.getProductionTime(timestampId));
        addString(timestamp, "producer", report.getProducedBy(timestampId));
        timestamp.addProperty("valid", report.isValid(timestampId));
        addEnum(timestamp, "qualification", report.getTimestampQualification(timestampId));
        return timestamp;
    }

    private static void addDate(JsonObject payload, String field, Date value) {
        if (value == null) {
            payload.add(field, JsonNull.INSTANCE);
            return;
        }
        payload.addProperty(field, Instant.ofEpochMilli(value.getTime()).toString());
    }

    private static void addString(JsonObject payload, String field, Object value) {
        if (value == null) {
            payload.add(field, JsonNull.INSTANCE);
            return;
        }
        payload.addProperty(field, value.toString());
    }

    private static void addEnum(JsonObject payload, String field, Enum<?> value) {
        if (value == null) {
            payload.add(field, JsonNull.INSTANCE);
            return;
        }
        payload.addProperty(field, value.name());
    }

    @FunctionalInterface
    interface ReportReader {
        SimpleReport read(Path path);
    }

    @FunctionalInterface
    interface ByteReportReader {
        SimpleReport read(byte[] content);
    }

    @FunctionalInterface
    interface ValidatorReportReader {
        SimpleReport read(SignedDocumentValidator validator);
    }

    private record AsicInspection(SimpleReport report, List<String> documents, Map<String, List<String>> coverage) {
    }
}
