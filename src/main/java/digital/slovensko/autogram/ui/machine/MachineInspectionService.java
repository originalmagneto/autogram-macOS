package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonNull;
import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.SignatureValidator;
import eu.europa.esig.dss.model.FileDocument;
import eu.europa.esig.dss.model.InMemoryDocument;
import eu.europa.esig.dss.pades.validation.PDFDocumentValidator;
import eu.europa.esig.dss.simplereport.SimpleReport;

import java.nio.file.Path;
import java.time.Instant;
import java.util.Date;

public final class MachineInspectionService {
    private final ReportReader reportReader;
    private final ByteReportReader byteReportReader;
    private final TimestampQualificationEvaluator timestampQualificationEvaluator;

    public MachineInspectionService() {
        this(MachineInspectionService::readTrustedReport);
    }

    MachineInspectionService(ReportReader reportReader) {
        this(reportReader, MachineInspectionService::readTrustedReport);
    }

    MachineInspectionService(ReportReader reportReader, ByteReportReader byteReportReader) {
        this.reportReader = reportReader;
        this.byteReportReader = byteReportReader;
        timestampQualificationEvaluator = new TimestampQualificationEvaluator();
    }

    public JsonObject inspect(Path path) {
        return mapReport(reportReader.read(path));
    }

    public JsonObject inspect(byte[] content) {
        return mapReport(byteReportReader.read(content));
    }

    static int readStructuralSignatureCount(Path path) {
        return new PDFDocumentValidator(new FileDocument(path.toFile())).getSignatures().size();
    }

    private static SimpleReport readTrustedReport(Path path) {
        var validator = new PDFDocumentValidator(new FileDocument(path.toFile()));
        return SignatureValidator.getInstance().validate(validator).getSimpleReport();
    }

    private static SimpleReport readTrustedReport(byte[] content) {
        var validator = new PDFDocumentValidator(new InMemoryDocument(content));
        return SignatureValidator.getInstance().validate(validator).getSimpleReport();
    }

    private JsonObject mapReport(SimpleReport report) {
        var payload = new JsonObject();
        var signatures = new com.google.gson.JsonArray();
        for (var signatureId : report.getSignatureIdList()) {
            signatures.add(mapSignature(report, signatureId));
        }
        payload.add("signatures", signatures);
        return payload;
    }

    private JsonObject mapSignature(SimpleReport report, String signatureId) {
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
}
