package digital.slovensko.autogram.ui.gui;

import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.layout.VBox;

import java.util.function.Consumer;

public class ConsentCertificateReadingDialogController implements SuppressedFocusController {
    private final Consumer<Runnable> callback;
    private final Runnable cancelCallback;
    private Runnable onClose;

    @FXML
    VBox mainBox;

    public ConsentCertificateReadingDialogController(Consumer<Runnable> callback, Runnable cancelCallback) {
        this.callback = callback;
        this.cancelCallback = cancelCallback;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void onContinueAction(ActionEvent event) {
        callback.accept(this::close);
    }

    public void onCancelAction(ActionEvent event) {
        if (cancelCallback != null) {
            cancelCallback.run();
        }
        close();
    }

    public void close() {
        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }
}
