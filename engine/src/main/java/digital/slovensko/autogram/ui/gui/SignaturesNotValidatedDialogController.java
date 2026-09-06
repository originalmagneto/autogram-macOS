package digital.slovensko.autogram.ui.gui;

import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.stage.Stage;

public class SignaturesNotValidatedDialogController implements SuppressedFocusController {
    private final SigningDialogController signigDialogController;
    private Runnable onClose;

    @FXML
    Button cancelButton;
    @FXML
    Button continueButton;
    @FXML
    Node mainBox;

    public SignaturesNotValidatedDialogController(SigningDialogController signigDialogController) {
        this.signigDialogController = signigDialogController;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void close() {
        if (onClose != null) {
            onClose.run();
        } else {
            var window = mainBox.getScene().getRoot().getScene().getWindow();
            if (window instanceof Stage)
                ((Stage) window).close();
        }

        signigDialogController.enableSigningOnAllJobs();
    }

    public void onCancelAction() {
        close();
        signigDialogController.close();
    }

    public void onContinueAction() {
        if (onClose != null) {
            onClose.run();
        } else {
            var window = mainBox.getScene().getRoot().getScene().getWindow();
            if (window instanceof Stage)
                ((Stage) window).close();
        }
        signigDialogController.sign();
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }
}
