package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.UserSettings;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.control.Button;


public class SettingsResetDialogController implements SuppressedFocusController {

    @FXML
    private Node mainBox;

    @FXML
    private Button confirmResetButton;

    @FXML
    private Button rejectResetButton;

    private UserSettings userSettings;
    private Runnable onClose;
    private Runnable onReset;


    public SettingsResetDialogController() {
    }


    public void onConfirmResetButtonAction() {

        if (userSettings != null) {
            userSettings.reset();
        }

        if (onReset != null) {
            onReset.run();
        }

        closeDialog();
    }

    public void onRejectResetButtonAction() {
        closeDialog();
    }


    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }

    public void setUserSettings(UserSettings userSettings) {
        this.userSettings = userSettings;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void setOnReset(Runnable onReset) {
        this.onReset = onReset;
    }

    private void closeDialog() {
        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
    }
}
