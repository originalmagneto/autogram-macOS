package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.Main;
import javafx.application.HostServices;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.control.Hyperlink;
import javafx.scene.text.Text;

public class AboutDialogController implements SuppressedFocusController {
    private final HostServices hostServices;
    @FXML
    Node mainBox;
    @FXML
    Hyperlink link;
    @FXML
    Text versionText;

    public AboutDialogController(HostServices hostServices) {
        this.hostServices = hostServices;
    }

    public void initialize() {
        versionText.setText(Main.getVersionString());
    }

    public void githubLinkAction(ActionEvent ignored) {
        hostServices.showDocument("https://github.com/slovensko-digital/autogram");
    }

    private Runnable onClose;

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void onCloseButtonAction(ActionEvent ignored) {
        if (onClose != null) {
            onClose.run();
        } else {
            // For now, About dialog implies it's in a stage if not in overlay, or handled
            // by OS window controls
            // But we added a close button, so we should try to close the window
            var window = mainBox.getScene().getWindow();
            if (window instanceof javafx.stage.Stage) {
                ((javafx.stage.Stage) window).close();
            }
        }
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }
}
