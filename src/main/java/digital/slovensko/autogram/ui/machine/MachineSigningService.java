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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
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
        int processedFiles = 0;
        try {
            MachineRequestValidator.validateSign(request);
            trustInitializer.run();
            try (var session = sessionFactory.apply(request)) {
                for (; processedFiles < request.files().size(); processedFiles++) {
                    signFile(requestId, session, request.files().get(processedFiles));
                }
            }
        } catch (Exception exception) {
            sessionFailed = true;
            failUnprocessedFiles(requestId, request.files().subList(processedFiles, request.files().size()),
                    "SIGNING_UNAVAILABLE");
        } finally {
            Arrays.fill(request.pin(), '\0');
        }

        if (sessionFailed) {
            writer.write("session.failed", requestId, null, failure("SIGNING_UNAVAILABLE"));
        } else {
            writer.write("session.completed", requestId, null, new JsonObject());
        }
    }

    private void signFile(String requestId, SigningSession session, MachineFile file) {
        writer.write("file.signingStarted", requestId, file.id(), new JsonObject());
        try {
            var completed = new boolean[] { false };
            session.sign(file, () -> completed[0] = true);
            if (!completed[0]) {
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            if (!outputValidator.isValid(Path.of(file.target()))) {
                deleteTarget(file.target());
                throw new MachineProtocolException("OUTPUT_VALIDATION_FAILED");
            }
            writer.write("file.completed", requestId, file.id(), new JsonObject());
        } catch (Exception exception) {
            var code = exception instanceof MachineProtocolException protocolException
                    && "OUTPUT_VALIDATION_FAILED".equals(protocolException.getMessage())
                    ? "OUTPUT_VALIDATION_FAILED"
                    : "SIGNING_FAILED";
            writer.write("file.failed", requestId, file.id(), failure(code));
        }
    }

    private void failUnprocessedFiles(String requestId, List<MachineFile> files, String code) {
        for (var file : files) {
            writer.write("file.signingStarted", requestId, file.id(), new JsonObject());
            writer.write("file.failed", requestId, file.id(), failure(code));
        }
    }

    private static JsonObject failure(String code) {
        var payload = new JsonObject();
        payload.addProperty("code", code);
        return payload;
    }

    private static void deleteTarget(String value) {
        try {
            Files.deleteIfExists(Path.of(value));
        } catch (IOException ignored) {
        }
    }

    interface SigningSession extends AutoCloseable {
        void sign(MachineFile file, Runnable completed) throws Exception;

        @Override
        void close();
    }

    @FunctionalInterface
    interface OutputValidator {
        boolean isValid(Path target) throws Exception;
    }

    private static final class DefaultSessionFactory implements Function<SignRequest, SigningSession> {
        private final MachineSettings settings;
        private final DriverDetector driverDetector;
        private final BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory;

        private DefaultSessionFactory() {
            this(new MachineSettings(true));
        }

        private DefaultSessionFactory(MachineSettings settings) {
            this(new DefaultDriverDetector(settings), settings, PasswordManager::new);
        }

        private DefaultSessionFactory(DriverDetector driverDetector, MachineSettings settings,
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

    private static final class DefaultSigningSession implements SigningSession {
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

        private static DefaultSigningSession open(TokenDriver driver, SignRequest request, MachineSettings settings,
                BiFunction<MachineSecretUI, MachineSettings, PasswordManager> passwordManagerFactory) {
            var secretUi = new MachineSecretUI(request.pin());
            var passwordManager = passwordManagerFactory.apply(secretUi, settings);
            AbstractKeyStoreTokenConnection token = null;
            try {
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
                        passwordManager.reset();
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
            var job = SigningJob.buildFromFile(Path.of(file.source()).toFile(), responder, false,
                    SignatureLevel.PAdES_BASELINE_T, false, settings.getTspSource(), true);
            job.signWithKeyAndRespond(key);
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

        private static DSSPrivateKeyEntry selectedKey(List<DSSPrivateKeyEntry> keys, String certificateSerial) {
            var matches = keys.stream().filter(key -> CliKeySelector.serial(key).equals(certificateSerial)).toList();
            if (matches.size() != 1) {
                throw new MachineProtocolException(matches.isEmpty() ? "CERTIFICATE_NOT_FOUND" : "CERTIFICATE_AMBIGUOUS");
            }
            return matches.getFirst();
        }
    }

    private static final class PdfOutputValidator implements OutputValidator {
        private final MachineInspectionService inspectionService;

        private PdfOutputValidator(MachineInspectionService inspectionService) {
            this.inspectionService = inspectionService;
        }

        @Override
        public boolean isValid(Path target) throws IOException {
            if (!hasPdfHeaderAndEof(target)) {
                return false;
            }
            var signatures = inspectionService.inspect(target).getAsJsonArray("signatures");
            return signatures.asList().stream().map(value -> value.getAsJsonObject()).anyMatch(signature ->
                    "PAdES_BASELINE_T".equals(string(signature, "format"))
                            && signature.has("qualifiedTimestampValid")
                            && signature.get("qualifiedTimestampValid").getAsBoolean());
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
