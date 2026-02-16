package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.SigningJob;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.control.Button;

public class PDFAComplianceDialogController implements SuppressedFocusController {
    private final SigningJob job;
    private final GUI gui;

    @FXML
    Node mainBox;
    @FXML
    Button continueButton;
    @FXML
    Button cancelButton;

    private Runnable onClose;
    private Runnable onContinue;

    public PDFAComplianceDialogController(SigningJob job, GUI gui) {
        this.job = job;
        this.gui = gui;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void setOnContinue(Runnable onContinue) {
        this.onContinue = onContinue;
    }

    public void onCancelAction(ActionEvent ignored) {
        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
        gui.cancelJob(job);
    }

    public void onContinueAction(ActionEvent ignored) {
        if (onContinue != null) {
            onContinue.run();
        }

        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
        gui.focusJob(job);
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }
}
