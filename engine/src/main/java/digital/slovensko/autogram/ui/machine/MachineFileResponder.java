package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.Responder;
import digital.slovensko.autogram.core.SignedDocument;
import digital.slovensko.autogram.core.errors.AutogramException;

import java.io.ByteArrayOutputStream;
import java.util.Objects;

public final class MachineFileResponder extends Responder {
    private final MachineSigningFileSystem.RetainedFile target;
    private final Runnable completed;

    MachineFileResponder(MachineSigningFileSystem.RetainedFile target, Runnable completed) {
        this.target = Objects.requireNonNull(target);
        this.completed = Objects.requireNonNull(completed);
    }

    @Override
    public void onDocumentSigned(SignedDocument signedDocument) {
        try {
            var content = new ByteArrayOutputStream();
            signedDocument.getDocument().writeTo(content);
            target.replaceContent(content.toByteArray());
            completed.run();
        } catch (Throwable exception) {
            throw new MachineProtocolException("OUTPUT_WRITE_FAILED", exception);
        }
    }

    @Override
    public void onDocumentSignFailed(AutogramException error) {
        throw new MachineProtocolException("SIGNING_FAILED", error);
    }

}
