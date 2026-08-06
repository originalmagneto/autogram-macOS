package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.DefaultDriverDetector;
import digital.slovensko.autogram.core.DriverDetector;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.SigningJob;
import digital.slovensko.autogram.core.SigningKey;
import digital.slovensko.autogram.core.SigningParameters;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.cli.CliKeySelector;
import eu.europa.esig.dss.enumerations.MimeTypeEnum;
import eu.europa.esig.dss.model.InMemoryDocument;
import eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection;
import eu.europa.esig.dss.token.DSSPrivateKeyEntry;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;
import java.util.function.BiFunction;
import java.util.function.Function;

public final class MachineSigningService {
    private final MachineEventWriter writer;
    private final Function<SignRequest, SigningSession> sessionFactory;
    private final OutputValidator outputValidator;
    private final Runnable trustInitializer;
    private final MachineSigningFileSystem fileSystem;

    public MachineSigningService(MachineEventWriter writer, MachineInspectionService inspectionService,
            Runnable trustInitializer) {
        this(writer, new DefaultSessionFactory(), new PdfOutputValidator(inspectionService), trustInitializer,
                MacNativeFileSystem.createForCurrentPlatform());
    }

    MachineSigningService(MachineEventWriter writer, Function<SignRequest, SigningSession> sessionFactory,
            OutputValidator outputValidator) {
        this(writer, sessionFactory, outputValidator, () -> { }, MacNativeFileSystem.createForCurrentPlatform());
    }

    MachineSigningService(MachineEventWriter writer, Function<SignRequest, SigningSession> sessionFactory,
            OutputValidator outputValidator, Runnable trustInitializer) {
        this(writer, sessionFactory, outputValidator, trustInitializer, MacNativeFileSystem.createForCurrentPlatform());
    }

    MachineSigningService(MachineEventWriter writer, Function<SignRequest, SigningSession> sessionFactory,
            OutputValidator outputValidator, Runnable trustInitializer, MachineSigningFileSystem fileSystem) {
        this.writer = Objects.requireNonNull(writer);
        this.sessionFactory = Objects.requireNonNull(sessionFactory);
        this.outputValidator = Objects.requireNonNull(outputValidator);
        this.trustInitializer = Objects.requireNonNull(trustInitializer);
        this.fileSystem = Objects.requireNonNull(fileSystem);
    }

    public String sign(String requestId, SignRequest request) {
        writer.write("session.started", requestId, null, new JsonObject());
        String sessionFailureCode = null;
        List<PreparedFile> preparedFiles = List.of();
        int processedFiles = 0;
        var requestFiles = request != null && request.files() != null ? request.files() : List.<MachineFile>of();
        var requestPin = request != null ? request.pin() : null;
        try {
            var validatedRequest = MachineRequestValidator.validateSign(request);
            preparedFiles = prepare(validatedRequest.files());
            for (var prepared : preparedFiles) {
                prepared.setPreviousSignatureIds(signatureIds(prepared.sourceContent()));
            }
            trustInitializer.run();
            try (var session = sessionFactory.apply(request)) {
                for (; processedFiles < preparedFiles.size(); processedFiles++) {
                    signFile(requestId, session, preparedFiles.get(processedFiles));
                }
            }
        } catch (Throwable exception) {
            sessionFailureCode = failureCode(exception, "SIGNING_UNAVAILABLE");
            int firstUnprocessed = Math.min(processedFiles, requestFiles.size());
            failUnprocessedFiles(requestId, requestFiles.subList(firstUnprocessed, requestFiles.size()), sessionFailureCode);
        } finally {
            if (!closePreparedFiles(preparedFiles)) {
                sessionFailureCode = "OUTPUT_CLEANUP_FAILED";
            }
            if (requestPin != null) {
                Arrays.fill(requestPin, '\0');
            }
        }

        if (sessionFailureCode != null) {
            var error = new MachineErrorMapper().map(new MachineProtocolException(sessionFailureCode));
            writer.writeTerminal("session.failed", requestId, error.toPayload());
        } else {
            writer.writeTerminal("session.completed", requestId, new JsonObject());
        }
        return sessionFailureCode;
    }

    private List<PreparedFile> prepare(List<ValidatedMachineFile> files) {
        var prepared = new ArrayList<PreparedFile>();
        try {
            for (var file : files) {
                prepared.add(PreparedFile.prepare(file, fileSystem));
            }
            return List.copyOf(prepared);
        } catch (Throwable exception) {
            if (!closePreparedFiles(prepared)) {
                throw new MachineProtocolException("OUTPUT_CLEANUP_FAILED", exception);
            }
            throw rethrow(exception);
        }
    }

    private void signFile(String requestId, SigningSession session, PreparedFile prepared) {
        var file = prepared.file();
        writer.write("file.signingStarted", requestId, file.id(), new JsonObject());
        try {
            var completed = new boolean[] { false };
            var previousSignatureIds = prepared.previousSignatureIds();
            session.sign(prepared.signingInput(), () -> completed[0] = true);
            if (!completed[0]) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            var signedContent = prepared.readSignedContent();
            if (!validOutput(signedContent, previousSignatureIds)) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            prepared.publish();
            writer.write("file.completed", requestId, file.id(), new JsonObject());
        } catch (Throwable exception) {
            var code = failureCode(exception, "SIGNING_FAILED");
            if (!prepared.cleanup()) {
                code = "OUTPUT_CLEANUP_FAILED";
            }
            writer.write("file.failed", requestId, file.id(), failure(code));
        }
    }

    private void failUnprocessedFiles(String requestId, List<MachineFile> files, String code) {
        for (var file : files) {
            var fileId = file == null ? null : file.id();
            writer.write("file.signingStarted", requestId, fileId, new JsonObject());
            writer.write("file.failed", requestId, fileId, failure(code));
        }
    }

    private Set<String> signatureIds(byte[] content) {
        try {
            return outputValidator.signatureIds(content);
        } catch (Throwable exception) {
            throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED", exception);
        }
    }

    private boolean validOutput(byte[] content, Set<String> previousSignatureIds) {
        try {
            return outputValidator.isValid(content, previousSignatureIds);
        } catch (Throwable exception) {
            throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED", exception);
        }
    }

    private static String failureCode(Throwable exception, String fallback) {
        if (exception instanceof MachineProtocolException protocolException) {
            return switch (protocolException.getMessage()) {
                case "OUTPUT_CLEANUP_FAILED", "OUTPUT_VALIDATION_FAILED", "OUTPUT_PUBLISH_UNSUPPORTED",
                        "OUTPUT_TARGET_EXISTS", "MACHINE_PLATFORM_UNSUPPORTED" -> protocolException.getMessage();
                default -> fallback;
            };
        }
        return fallback;
    }

    private static MachineProtocolException rethrow(Throwable exception) {
        if (exception instanceof RuntimeException runtimeException) {
            throw runtimeException;
        }
        if (exception instanceof Error error) {
            throw error;
        }
        return new MachineProtocolException("SIGNING_UNAVAILABLE", exception);
    }

    private static JsonObject failure(String code) {
        var payload = new JsonObject();
        payload.addProperty("code", code);
        return payload;
    }

    private static boolean closePreparedFiles(List<PreparedFile> preparedFiles) {
        var cleaned = true;
        for (var prepared : preparedFiles) {
            try {
                cleaned &= prepared.cleanup();
            } catch (Throwable exception) {
                cleaned = false;
            }
        }
        return cleaned;
    }

    private static final class PreparedFile {
        private final MachineFile file;
        private final Path target;
        private final MachineSigningFileSystem.RetainedFile source;
        private final MachineSigningFileSystem.RetainedFile staging;
        private final MachineSigningFileSystem.Workspace workspace;
        private final byte[] sourceContent;
        private Set<String> previousSignatureIds;
        private boolean cleaned;

        private PreparedFile(MachineFile file, Path target, MachineSigningFileSystem.RetainedFile source,
                MachineSigningFileSystem.RetainedFile staging, MachineSigningFileSystem.Workspace workspace,
                byte[] sourceContent) {
            this.file = file;
            this.target = target;
            this.source = source;
            this.staging = staging;
            this.workspace = workspace;
            this.sourceContent = sourceContent;
        }

        private static PreparedFile prepare(ValidatedMachineFile validated, MachineSigningFileSystem fileSystem)
                throws IOException {
            var file = validated.file();
            MachineSigningFileSystem.RetainedFile source = null;
            MachineSigningFileSystem.Workspace workspace = null;
            try {
                source = fileSystem.openSource(validated.source());
                var sourceContent = source.readAll();
                if (!hasPdfHeader(sourceContent)) {
                    throw new IOException("Source is not a PDF");
                }
                workspace = fileSystem.createWorkspace(validated.target().getParent());
                var staging = workspace.createStagingFile();
                return new PreparedFile(file, validated.target(), source, staging, workspace, sourceContent);
            } catch (Throwable exception) {
                boolean cleaned = true;
                if (workspace != null) {
                    try {
                        cleaned &= workspace.cleanup();
                    } catch (Throwable cleanupFailure) {
                        cleaned = false;
                    }
                }
                if (source != null) {
                    try {
                        source.close();
                    } catch (Throwable cleanupFailure) {
                        cleaned = false;
                    }
                }
                if (!cleaned) {
                    throw new MachineProtocolException("OUTPUT_CLEANUP_FAILED", exception);
                }
                throw rethrow(exception);
            }
        }

        private MachineFile file() {
            return file;
        }

        private void setPreviousSignatureIds(Set<String> value) {
            previousSignatureIds = Set.copyOf(value);
        }

        private Set<String> previousSignatureIds() {
            if (previousSignatureIds == null) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            return previousSignatureIds;
        }

        private SigningInput signingInput() {
            return new SigningInput(file, sourceContent.clone(), source, staging);
        }

        private byte[] sourceContent() {
            return sourceContent.clone();
        }

        private byte[] readSignedContent() throws IOException {
            return staging.readAll();
        }

        private void publish() throws IOException {
            workspace.publish(staging, target.getFileName().toString());
        }

        private boolean cleanup() {
            if (cleaned) {
                return true;
            }
            boolean success = true;
            try {
                source.close();
            } catch (Throwable exception) {
                success = false;
            }
            try {
                success &= workspace.cleanup();
            } catch (Throwable exception) {
                success = false;
            }
            cleaned = success;
            return success;
        }
    }

    record SigningInput(MachineFile file, byte[] sourceContent, MachineSigningFileSystem.RetainedFile source,
            MachineSigningFileSystem.RetainedFile staging) {
        SigningInput {
            sourceContent = sourceContent.clone();
        }

        void writeSignedContent(byte[] content) throws IOException {
            staging.replaceContent(content);
        }
    }

    private static boolean hasPdfHeader(byte[] content) {
        return content.length >= 5 && "%PDF-".equals(new String(content, 0, 5, StandardCharsets.ISO_8859_1));
    }

    private static byte[] readAll(FileChannel input) throws IOException {
        var content = new ByteArrayOutputStream();
        var buffer = java.nio.ByteBuffer.allocate(8192);
        while (input.read(buffer) != -1) {
            buffer.flip();
            content.write(buffer.array(), 0, buffer.remaining());
            buffer.clear();
        }
        return content.toByteArray();
    }

    interface SigningSession extends AutoCloseable {
        void sign(SigningInput input, Runnable completed) throws Exception;

        @Override
        void close();
    }

    @FunctionalInterface
    interface OutputValidator {
        boolean isValid(byte[] content) throws Exception;

        default boolean isValid(byte[] content, Set<String> previousSignatureIds) throws Exception {
            return isValid(content);
        }

        default Set<String> signatureIds(byte[] content) throws Exception {
            return Set.of();
        }
    }

    static final class DefaultSessionFactory implements Function<SignRequest, SigningSession> {
        private final MachineSettings settings;
        private final DriverDetector driverDetector;
        private final BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory;

        DefaultSessionFactory() {
            this(new MachineSettings(true));
        }

        DefaultSessionFactory(MachineSettings settings) {
            this(new DefaultDriverDetector(settings), settings, PasswordManager::new);
        }

        DefaultSessionFactory(DriverDetector driverDetector, MachineSettings settings,
                BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory) {
            this.driverDetector = driverDetector;
            this.settings = settings;
            this.passwordManagerFactory = passwordManagerFactory;
        }

        @Override
        public SigningSession apply(SignRequest request) {
            settings.setTsaServer(String.join(",", request.timestamp().servers()));
            settings.setTsaEnabled(true);
            var driver = driverDetector.getAvailableDrivers().stream()
                    .filter(candidate -> candidate.getShortname().equals(request.driver()))
                    .findFirst()
                    .orElseThrow(() -> new MachineProtocolException("DRIVER_NOT_FOUND"));
            return DefaultSigningSession.open(driver, request, settings, passwordManagerFactory);
        }
    }

    static final class DefaultSigningSession implements SigningSession {
        private final MachineSecretUI secretUi;
        private final PasswordManager passwordManager;
        private final AbstractKeyStoreTokenConnection token;
        private final SigningKey key;
        private final MachineSettings settings;

        private DefaultSigningSession(MachineSecretUI secretUi, PasswordManager passwordManager,
                AbstractKeyStoreTokenConnection token, SigningKey key, MachineSettings settings) {
            this.secretUi = secretUi;
            this.passwordManager = passwordManager;
            this.token = token;
            this.key = key;
            this.settings = settings;
        }

        static DefaultSigningSession open(TokenDriver driver, SignRequest request, MachineSettings settings,
                BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory) {
            var secretUi = new MachineSecretUI(request.pin());
            PasswordManager passwordManager = null;
            AbstractKeyStoreTokenConnection token = null;
            try {
                passwordManager = passwordManagerFactory.apply(secretUi, settings);
                token = driver.createToken(passwordManager, settings);
                var key = selectedKey(token.getKeys(), request.certificateSerial());
                return new DefaultSigningSession(secretUi, passwordManager, token, new SigningKey(token, key), settings);
            } catch (Throwable exception) {
                try {
                    if (token != null) {
                        token.close();
                    }
                } finally {
                    try {
                        if (passwordManager != null) {
                            passwordManager.reset();
                        }
                    } finally {
                        secretUi.close();
                    }
                }
                throw exception;
            }
        }

        @Override
        public void sign(SigningInput input, Runnable completed) throws Exception {
            var responder = new MachineFileResponder(input.staging(), completed);
            var job = signingJob(input.sourceContent(), input.file().source(), responder, settings);
            job.signWithKeyAndRespond(key);
        }

        static SigningJob signingJob(byte[] source, String name, MachineFileResponder responder, MachineSettings settings)
                throws Exception {
            var document = new InMemoryDocument(source, Path.of(name).getFileName().toString(), MimeTypeEnum.PDF);
            var parameters = SigningParameters.buildForPDF(document, false, false, settings.getTspSource());
            return SigningJob.buildFromRequest(document, parameters, responder);
        }

        @Override
        public void close() {
            try {
                token.close();
            } finally {
                try {
                    passwordManager.reset();
                } finally {
                    secretUi.close();
                }
            }
        }

        static DSSPrivateKeyEntry selectedKey(List<DSSPrivateKeyEntry> keys, String certificateSerial) {
            var matches = keys.stream().filter(key -> CliKeySelector.serial(key).equals(certificateSerial)).toList();
            if (matches.size() != 1) {
                throw new MachineProtocolException(matches.isEmpty() ? "CERTIFICATE_NOT_FOUND" : "CERTIFICATE_AMBIGUOUS");
            }
            return matches.getFirst();
        }
    }

    static final class PdfOutputValidator implements OutputValidator {
        private final MachineInspectionService inspectionService;

        PdfOutputValidator(MachineInspectionService inspectionService) {
            this.inspectionService = inspectionService;
        }

        boolean isValid(Path target) throws IOException {
            return isValid(readPathNoFollow(target), Set.of());
        }

        Set<String> signatureIds(Path target) throws IOException {
            return signatureIds(readPathNoFollow(target));
        }

        @Override
        public Set<String> signatureIds(byte[] content) throws IOException {
            var signatures = inspectionService.inspect(content).getAsJsonArray("signatures");
            var ids = new HashSet<String>();
            for (var value : signatures) {
                var signature = value.getAsJsonObject();
                var id = string(signature, "id");
                if (id == null) {
                    throw new IOException("Signature has no identity");
                }
                ids.add(id);
            }
            return Set.copyOf(ids);
        }

        boolean isValid(Path target, Set<String> previousSignatureIds) throws IOException {
            return isValid(readPathNoFollow(target), previousSignatureIds);
        }

        @Override
        public boolean isValid(byte[] content, Set<String> previousSignatureIds) {
            if (!hasPdfHeaderAndEof(content)) {
                return false;
            }
            var signatures = inspectionService.inspect(content).getAsJsonArray("signatures");
            var added = signatures.asList().stream().map(value -> value.getAsJsonObject())
                    .filter(signature -> !previousSignatureIds.contains(string(signature, "id"))).toList();
            return added.size() == 1
                    && "PAdES_BASELINE_T".equals(string(added.getFirst(), "format"))
                    && added.getFirst().has("valid")
                    && added.getFirst().get("valid").getAsBoolean()
                    && "TOTAL_PASSED".equals(string(added.getFirst(), "indication"))
                    && added.getFirst().has("qualifiedTimestampValid")
                    && added.getFirst().get("qualifiedTimestampValid").getAsBoolean();
        }

        @Override
        public boolean isValid(byte[] content) {
            return isValid(content, Set.of());
        }

        private static byte[] readPathNoFollow(Path target) throws IOException {
            try (var input = FileChannel.open(target, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
                return readAll(input);
            }
        }

        private static boolean hasPdfHeaderAndEof(byte[] bytes) {
            if (bytes.length < 10 || !hasPdfHeader(bytes)) {
                return false;
            }
            var content = new String(bytes, StandardCharsets.ISO_8859_1);
            return content.stripTrailing().endsWith("%%EOF");
        }

        private static String string(JsonObject value, String field) {
            return value.has(field) && !value.get(field).isJsonNull() ? value.get(field).getAsString() : null;
        }
    }
}

record SignRequest(
        String driver,
        String certificateSerial,
        char[] pin,
        String signatureLevel,
        QualifiedTimestampRequest timestamp,
        List<MachineFile> files) {
}

record QualifiedTimestampRequest(boolean required, List<String> servers) {
}
