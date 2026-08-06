package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.Responder;
import digital.slovensko.autogram.core.SignedDocument;
import digital.slovensko.autogram.core.errors.AutogramException;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Objects;
import java.util.function.Consumer;

public final class MachineFileResponder extends Responder {
    private final Path target;
    private final Consumer<Path> completed;

    public MachineFileResponder(Path target, Consumer<Path> completed) {
        this.target = Objects.requireNonNull(target);
        this.completed = Objects.requireNonNull(completed);
    }

    @Override
    public void onDocumentSigned(SignedDocument signedDocument) {
        try {
            Files.createFile(target);
            signedDocument.getDocument().save(target.toString());
            completed.accept(target);
        } catch (IOException | RuntimeException exception) {
            throw new MachineProtocolException("OUTPUT_WRITE_FAILED", exception);
        }
    }

    @Override
    public void onDocumentSignFailed(AutogramException error) {
        throw new MachineProtocolException("SIGNING_FAILED", error);
    }

}
