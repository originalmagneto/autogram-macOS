package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;
import digital.slovensko.autogram.core.DefaultDriverDetector;
import digital.slovensko.autogram.core.DriverDetector;
import digital.slovensko.autogram.core.PasswordManager;
import digital.slovensko.autogram.core.SigningJob;
import digital.slovensko.autogram.core.SigningKey;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.cli.CliKeySelector;
import eu.europa.esig.dss.enumerations.SignatureLevel;
import eu.europa.esig.dss.token.AbstractKeyStoreTokenConnection;
import eu.europa.esig.dss.token.DSSPrivateKeyEntry;

import java.io.IOException;
import java.nio.channels.Channels;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.LinkOption;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
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

    public MachineSigningService(MachineEventWriter writer, MachineInspectionService inspectionService,
            Runnable trustInitializer) {
        this(writer, new DefaultSessionFactory(), new PdfOutputValidator(inspectionService), trustInitializer);
    }

    MachineSigningService(MachineEventWriter writer, Function<SignRequest, SigningSession> sessionFactory,
            OutputValidator outputValidator) {
        this(writer, sessionFactory, outputValidator, () -> { });
    }

    MachineSigningService(MachineEventWriter writer, Function<SignRequest, SigningSession> sessionFactory,
            OutputValidator outputValidator, Runnable trustInitializer) {
        this.writer = Objects.requireNonNull(writer);
        this.sessionFactory = Objects.requireNonNull(sessionFactory);
        this.outputValidator = Objects.requireNonNull(outputValidator);
        this.trustInitializer = Objects.requireNonNull(trustInitializer);
    }

    public void sign(String requestId, SignRequest request) {
        writer.write("session.started", requestId, null, new JsonObject());
        boolean sessionFailed = false;
        List<PreparedFile> preparedFiles = List.of();
        int processedFiles = 0;
        try {
            var validatedRequest = MachineRequestValidator.validateSign(request);
            preparedFiles = prepare(validatedRequest.files());
            for (var prepared : preparedFiles) {
                prepared.setPreviousSignatureIds(signatureIds(prepared.snapshot()));
            }
            trustInitializer.run();
            try (var session = sessionFactory.apply(request)) {
                for (; processedFiles < preparedFiles.size(); processedFiles++) {
                    signFile(requestId, session, preparedFiles.get(processedFiles));
                }
            }
        } catch (Exception exception) {
            sessionFailed = true;
            failUnprocessedFiles(requestId, request.files().subList(processedFiles, request.files().size()),
                    "SIGNING_UNAVAILABLE");
        } finally {
            closePreparedFiles(preparedFiles);
            Arrays.fill(request.pin(), '\0');
        }

        if (sessionFailed) {
            writer.write("session.failed", requestId, null, failure("SIGNING_UNAVAILABLE"));
        } else {
            writer.write("session.completed", requestId, null, new JsonObject());
        }
    }

    private List<PreparedFile> prepare(List<ValidatedMachineFile> files) throws IOException {
        var workspace = Files.createTempDirectory("autogram-machine-sign-");
        var prepared = new ArrayList<PreparedFile>();
        try {
            for (var file : files) {
                prepared.add(PreparedFile.prepare(workspace, file));
            }
            return List.copyOf(prepared);
        } catch (IOException | RuntimeException exception) {
            closePreparedFiles(prepared);
            deleteWorkspace(workspace);
            throw exception;
        }
    }

    private void signFile(String requestId, SigningSession session, PreparedFile prepared) {
        var file = prepared.file();
        writer.write("file.signingStarted", requestId, file.id(), new JsonObject());
        try {
            var completed = new boolean[] { false };
            var previousSignatureIds = prepared.previousSignatureIds();
            session.sign(prepared.signingFile(), () -> completed[0] = true);
            if (!completed[0]) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            if (!validOutput(prepared.staging(), previousSignatureIds)) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            prepared.copyStagingToOwnedTarget();
            prepared.markSuccessful();
            writer.write("file.completed", requestId, file.id(), new JsonObject());
        } catch (Exception exception) {
            var code = exception instanceof MachineProtocolException protocolException
                    && "OUTPUT_VALIDATION_FAILED".equals(protocolException.getMessage())
                    ? "OUTPUT_VALIDATION_FAILED"
                    : "SIGNING_FAILED";
            if (!prepared.cleanupFailedOutput()) {
                code = "OUTPUT_CLEANUP_FAILED";
            }
            writer.write("file.failed", requestId, file.id(), failure(code));
        }
    }

    private void failUnprocessedFiles(String requestId, List<MachineFile> files, String code) {
        for (var file : files) {
            writer.write("file.signingStarted", requestId, file.id(), new JsonObject());
            writer.write("file.failed", requestId, file.id(), failure(code));
        }
    }

    private Set<String> signatureIds(Path path) {
        try {
            return outputValidator.signatureIds(path);
        } catch (Exception exception) {
            throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED", exception);
        }
    }

    private boolean validOutput(Path path, Set<String> previousSignatureIds) {
        try {
            return outputValidator.isValid(path, previousSignatureIds);
        } catch (Exception exception) {
            throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED", exception);
        }
    }

    private static JsonObject failure(String code) {
        var payload = new JsonObject();
        payload.addProperty("code", code);
        return payload;
    }

    private static void closePreparedFiles(List<PreparedFile> preparedFiles) {
        for (var prepared : preparedFiles) {
            prepared.close();
        }
        if (!preparedFiles.isEmpty()) {
            deleteWorkspace(preparedFiles.getFirst().workspace());
        }
    }

    private static void deleteWorkspace(Path workspace) {
        try {
            Files.deleteIfExists(workspace);
        } catch (IOException ignored) {
        }
    }

    private static final class PreparedFile implements AutoCloseable {
        private final Path workspace;
        private final MachineFile file;
        private final Path snapshot;
        private final Path staging;
        private final OwnedTarget target;
        private final MachineFileIdentity snapshotIdentity;
        private MachineFileIdentity stagingIdentity;
        private Set<String> previousSignatureIds;
        private boolean successful;

        private PreparedFile(Path workspace, MachineFile file, Path snapshot, Path staging, OwnedTarget target,
                MachineFileIdentity snapshotIdentity) {
            this.workspace = workspace;
            this.file = file;
            this.snapshot = snapshot;
            this.staging = staging;
            this.target = target;
            this.snapshotIdentity = snapshotIdentity;
        }

        private static PreparedFile prepare(Path workspace, ValidatedMachineFile validated) throws IOException {
            var file = validated.file();
            var snapshot = Files.createTempFile(workspace, "source-", ".pdf");
            try {
                copySourceSnapshot(validated.source(), validated.sourceIdentity(), snapshot);
                var staging = workspace.resolve("staging-" + snapshot.getFileName());
                var target = OwnedTarget.reserve(validated.target());
                return new PreparedFile(workspace, file, snapshot, staging, target, MachineFileIdentity.capture(snapshot));
            } catch (IOException | RuntimeException exception) {
                Files.deleteIfExists(snapshot);
                throw exception;
            }
        }

        private static void copySourceSnapshot(Path source, MachineFileIdentity expected, Path snapshot) throws IOException {
            expected.verify(source);
            try (var input = FileChannel.open(source, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS);
                    var output = FileChannel.open(snapshot, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING)) {
                expected.verify(source);
                OwnedTarget.copy(input, output);
                output.force(true);
            }
            expected.verify(source);
            try (var input = Channels.newInputStream(FileChannel.open(snapshot, StandardOpenOption.READ))) {
                if (!"%PDF-".equals(new String(input.readNBytes(5), StandardCharsets.ISO_8859_1))) {
                    throw new IOException("Snapshot is not a PDF");
                }
            }
        }

        private MachineFile file() {
            return file;
        }

        private Path workspace() {
            return workspace;
        }

        private Path snapshot() {
            return snapshot;
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

        private Path staging() {
            return staging;
        }

        private MachineFile signingFile() {
            return new MachineFile(file.id(), snapshot.toString(), staging.toString());
        }

        private void copyStagingToOwnedTarget() throws IOException {
            captureStagingIdentity();
            target.copyFrom(staging);
        }

        private boolean validateOwnedTarget(OutputValidation validation, Set<String> previousSignatureIds) throws Exception {
            target.verifyCurrentPath();
            var valid = validation.isValid(target.path(), previousSignatureIds);
            target.verifyCurrentPath();
            return valid;
        }

        private void markSuccessful() throws IOException {
            target.verifyCurrentPath();
            successful = true;
        }

        private boolean cleanupFailedOutput() {
            try {
                target.deleteOwned();
                deleteOwned(staging, stagingIdentity);
                return true;
            } catch (IOException exception) {
                return false;
            }
        }

        private void captureStagingIdentity() throws IOException {
            stagingIdentity = MachineFileIdentity.capture(staging);
        }

        private static void deleteOwned(Path path, MachineFileIdentity identity) throws IOException {
            if (identity == null) {
                return;
            }
            identity.verify(path);
            Files.delete(path);
        }

        @Override
        public void close() {
            if (!successful) {
                cleanupFailedOutput();
            }
            target.close();
            try {
                deleteOwned(staging, stagingIdentity);
                deleteOwned(snapshot, snapshotIdentity);
            } catch (IOException ignored) {
            }
        }
    }

    private static final class OwnedTarget implements AutoCloseable {
        private final Path path;
        private final FileChannel channel;
        private final Object fileKey;

        private OwnedTarget(Path path, FileChannel channel, Object fileKey) {
            this.path = path;
            this.channel = channel;
            this.fileKey = fileKey;
        }

        private static OwnedTarget reserve(Path path) throws IOException {
            var channel = FileChannel.open(path, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE,
                    LinkOption.NOFOLLOW_LINKS);
            MachineFileIdentity reservedIdentity = null;
            try {
                var attributes = attributes(path);
                if (!attributes.isRegularFile() || attributes.fileKey() == null) {
                    throw new IOException("Reserved target has no stable file identity");
                }
                reservedIdentity = MachineFileIdentity.capture(path);
                return new OwnedTarget(path, channel, attributes.fileKey());
            } catch (IOException | RuntimeException exception) {
                channel.close();
                if (reservedIdentity != null) {
                    try {
                        reservedIdentity.verify(path);
                        Files.delete(path);
                    } catch (IOException ignored) {
                    }
                }
                throw exception;
            }
        }

        private Path path() {
            return path;
        }

        private void copyFrom(Path staging) throws IOException {
            verifyCurrentPath();
            channel.truncate(0);
            channel.position(0);
            try (var input = FileChannel.open(staging, StandardOpenOption.READ)) {
                copy(input, channel);
            }
            channel.force(true);
            verifyCurrentPath();
        }

        private void verifyCurrentPath() throws IOException {
            var attributes = attributes(path);
            if (!attributes.isRegularFile() || !Objects.equals(fileKey, attributes.fileKey())) {
                throw new IOException("Target ownership changed");
            }
        }

        private void deleteOwned() throws IOException {
            verifyCurrentPath();
            Files.delete(path);
        }

        private static BasicFileAttributes attributes(Path path) throws IOException {
            return Files.readAttributes(path, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        }

        private static void copy(FileChannel input, FileChannel output) throws IOException {
            long position = 0;
            while (position < input.size()) {
                var copied = input.transferTo(position, input.size() - position, output);
                if (copied <= 0) {
                    throw new IOException("Could not copy file");
                }
                position += copied;
            }
        }

        @Override
        public void close() {
            try {
                channel.close();
            } catch (IOException ignored) {
            }
        }
    }

    @FunctionalInterface
    private interface OutputValidation {
        boolean isValid(Path path, Set<String> previousSignatureIds);
    }

    interface SigningSession extends AutoCloseable {
        void sign(MachineFile file, Runnable completed) throws Exception;

        @Override
        void close();
    }

    @FunctionalInterface
    interface OutputValidator {
        boolean isValid(Path target) throws Exception;

        default Set<String> signatureIds(Path target) throws Exception {
            return Set.of();
        }

        default boolean isValid(Path target, Set<String> previousSignatureIds) throws Exception {
            return isValid(target);
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
            } catch (Exception exception) {
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
        public void sign(MachineFile file, Runnable completed) throws Exception {
            var responder = new MachineFileResponder(Path.of(file.target()), ignored -> completed.run());
            var job = signingJob(Path.of(file.source()), responder, settings);
            job.signWithKeyAndRespond(key);
        }

        static SigningJob signingJob(Path source, MachineFileResponder responder, MachineSettings settings) {
            return SigningJob.buildFromFile(source.toFile(), responder, false,
                    SignatureLevel.PAdES_BASELINE_T, false, settings.getTspSource(), true);
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

        @Override
        public boolean isValid(Path target) throws IOException {
            return isValid(target, Set.of());
        }

        @Override
        public Set<String> signatureIds(Path target) throws IOException {
            var signatures = inspectionService.inspect(target).getAsJsonArray("signatures");
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

        @Override
        public boolean isValid(Path target, Set<String> previousSignatureIds) throws IOException {
            if (!hasPdfHeaderAndEof(target)) {
                return false;
            }
            var signatures = inspectionService.inspect(target).getAsJsonArray("signatures");
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

        private static boolean hasPdfHeaderAndEof(Path target) throws IOException {
            if (!Files.isRegularFile(target) || Files.size(target) < 10) {
                return false;
            }
            var bytes = Files.readAllBytes(target);
            var content = new String(bytes, StandardCharsets.ISO_8859_1);
            return content.startsWith("%PDF-") && content.stripTrailing().endsWith("%%EOF");
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
