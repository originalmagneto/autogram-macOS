package digital.slovensko.autogram.ui.gui;

import javafx.concurrent.Worker;
import javafx.fxml.FXML;
import javafx.scene.control.Button;
import javafx.scene.layout.VBox;
import javafx.scene.web.WebView;

public class SignatureDetailsController {
    private final String htmlReport;
    private Runnable onClose;
    @FXML
    VBox mainBox;
    @FXML
    Button closeButton;
    @FXML
    WebView webView;
    @FXML
    VBox webViewContainer;

    public SignatureDetailsController(String htmlReport) {
        this.htmlReport = htmlReport;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void onCloseButtonAction() {
        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
    }

    public void initialize() {
        webView.setContextMenuEnabled(false);
        webView.getEngine().setJavaScriptEnabled(true);
        var engine = webView.getEngine();
        engine.getLoadWorker().stateProperty().addListener((observable, oldState, newState) -> {
            if (newState == Worker.State.SUCCEEDED) {
                engine.getDocument().getElementById("frame").setAttribute("srcdoc", htmlReport);
            }
        });
        engine.load(getClass().getResource("signature-details.html").toExternalForm());
        webViewContainer.setVisible(true);
        webViewContainer.setManaged(true);
    }
}
