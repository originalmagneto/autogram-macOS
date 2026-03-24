package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.Autogram;
import digital.slovensko.autogram.core.SignatureValidator;
import digital.slovensko.autogram.core.errors.AutogramException;

import digital.slovensko.autogram.core.visualization.Visualization;
import digital.slovensko.autogram.ui.Visualizer;
import digital.slovensko.autogram.util.DSSUtils;
import eu.europa.esig.dss.validation.reports.Reports;
import eu.europa.esig.dss.model.DSSDocument;
import javafx.concurrent.Worker;
import javafx.event.ActionEvent;
import javafx.event.Event;
import javafx.fxml.FXML;
import javafx.scene.Cursor;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.ScrollPane;
import javafx.scene.control.TextArea;
import javafx.scene.control.Tooltip;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.input.ContextMenuEvent;
import javafx.scene.layout.FlowPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;
import javafx.scene.web.WebView;
import javafx.stage.Modality;
import javafx.stage.Stage;

import java.io.ByteArrayInputStream;
import java.io.IOException;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

import static digital.slovensko.autogram.ui.gui.GUIValidationUtils.*;

public class SigningDialogController implements SuppressedFocusController, Visualizer {
    private final GUI gui;
    private final Autogram autogram;
    private final String title;
    private SignaturesController signaturesController;
    private SignaturesNotValidatedDialogController signaturesNotValidatedDialogController;
    private boolean signatureValidationCompleted = false;
    private boolean signatureCheckCompleted = false;
    private final Visualization visualization;
    private Reports signatureValidationReports;
    private Reports signatureCheckReports;
    private final boolean shouldCheckValidityBeforeSigning;
    private MainMenuController mainMenuController;

    @FXML
    VBox mainBox;
    @FXML
    TextArea plainTextArea;
    @FXML
    WebView webView;
    @FXML
    VBox webViewContainer;
    @FXML
    ScrollPane pdfVisualizationContainer;
    @FXML
    VBox pdfVisualizationBox;
    @FXML
    ImageView imageVisualization;
    @FXML
    ScrollPane imageVisualizationContainer;
    @FXML
    public Button mainButton;
    @FXML
    public Button changeKeyButton;
    @FXML
    VBox unsupportedVisualizationInfoBox;
    @FXML
    VBox signaturesTable;
    @FXML
    Text headerText;
    @FXML
    Label signingStateLabel;
    @FXML
    Label headerHelpLabel;
    @FXML
    FlowPane signingBadgeRow;
    @FXML
    Label documentTypeBadge;
    @FXML
    Label signatureStateBadge;
    @FXML
    Label activeCertificateLabel;
    @FXML
    javafx.scene.control.ChoiceBox<eu.europa.esig.dss.enumerations.SignatureLevel> signatureFormatChoice;
    @FXML
    javafx.scene.control.CheckBox timestampCheckbox;
    @FXML
    Label stepPreviewLabel;
    @FXML
    Label stepSignaturesLabel;
    @FXML
    Label stepSigningLabel;
    @FXML
    VBox inlineAlertsBox;

    private static final String ALERT_PDFA = "pdfa";
    private static final String ALERT_SIGNATURES_PENDING = "signatures-pending";
    private static final String ALERT_SIGNATURES_INVALID = "signatures-invalid";
    private static final String ALERT_SIGNING_ERROR = "signing-error";
    private final Map<String, VBox> inlineAlerts = new HashMap<>();

    public SigningDialogController(Visualization visualization, Autogram autogram, GUI gui, String title,
            boolean shouldCheckValidityBeforeSigning) {
        this.visualization = visualization;
        this.gui = gui;
        this.autogram = autogram;
        this.title = title;
        this.shouldCheckValidityBeforeSigning = shouldCheckValidityBeforeSigning;
    }

    public void initialize() throws IOException {
        headerText.setText(title);
        setActiveStep(1);
        signaturesTable.setManaged(false);
        signaturesTable.setVisible(false);
        configureHeader();
        if (shouldCheckValidityBeforeSigning) {
            showInlineInfoAlert(ALERT_SIGNATURES_PENDING, "Kontrola podpisov prebieha",
                    "Overujem existujúce podpisy v dokumente. Môžete pokračovať v čítaní dokumentu.");
        }
        refreshSigningKey();
        visualization.initialize(this);
        autogram.checkPDFACompliance(visualization.getJob());

        // Initialize Signature Options
        if (signatureFormatChoice != null) {
            signatureFormatChoice.setConverter(new SignatureLevelStringConverter());
            signatureFormatChoice.getItems().addAll(
                    eu.europa.esig.dss.enumerations.SignatureLevel.PAdES_BASELINE_B,
                    eu.europa.esig.dss.enumerations.SignatureLevel.XAdES_BASELINE_B,
                    eu.europa.esig.dss.enumerations.SignatureLevel.CAdES_BASELINE_B);

            var settings = autogram.getUserSettings();
            signatureFormatChoice.setValue(settings.getSignatureLevel());
            signatureFormatChoice.getSelectionModel().selectedItemProperty().addListener((obs, oldVal, newVal) -> {
                if (newVal != null) {
                    settings.setSignatureLevel(newVal);
                    settings.save();
                }
            });
        }

        if (timestampCheckbox != null) {
            var settings = autogram.getUserSettings();
            timestampCheckbox.setSelected(settings.getTsaEnabled());
            timestampCheckbox.selectedProperty().addListener((obs, oldVal, newVal) -> {
                settings.setTsaEnabled(newVal);
                settings.save();
            });
        }
    }

    public void setMainMenuController(MainMenuController mainMenuController) {
        this.mainMenuController = mainMenuController;
    }

    public void onMainButtonPressed(ActionEvent event) {
        checkExistingSignatureValidityAndSign();
    }

    private void showSignaturesNotValidatedDialog() {
        if (signaturesNotValidatedDialogController == null)
            signaturesNotValidatedDialogController = new SignaturesNotValidatedDialogController(this);

        var root = GUIUtils.loadFXML(signaturesNotValidatedDialogController, "signatures-not-validated-dialog.fxml");
        if (mainMenuController != null) {
            signaturesNotValidatedDialogController.setOnClose(mainMenuController::hideOverlayDialog);
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#continueButton")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("Upozornenie");
            stage.setScene(new Scene(root));

            stage.sizeToScene();
            stage.initModality(Modality.WINDOW_MODAL);
            stage.initOwner(mainButton.getScene().getWindow());
            stage.setOnCloseRequest(event -> signaturesNotValidatedDialogController.close());

            GUIUtils.suppressDefaultFocus(stage, signaturesNotValidatedDialogController);

            stage.show();
        }
    }

    private void showSignaturesInvalidDialog() {
        var signaturesInvalidDialogController = new SignaturesInvalidDialogController(this, signatureValidationReports);

        var root = GUIUtils.loadFXML(signaturesInvalidDialogController, "signatures-invalid-dialog.fxml");
        if (mainMenuController != null) {
            signaturesInvalidDialogController.setOnClose(mainMenuController::hideOverlayDialog);
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#continueButton")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("Upozornenie");
            stage.setScene(new Scene(root));

            stage.sizeToScene();
            stage.initModality(Modality.WINDOW_MODAL);
            stage.initOwner(mainButton.getScene().getWindow());
            stage.setOnCloseRequest(event -> signaturesInvalidDialogController.close());

            GUIUtils.suppressDefaultFocus(stage, signaturesInvalidDialogController);

            stage.show();
        }
    }

    private void checkExistingSignatureValidityAndSign() {
        if (!shouldCheckValidityBeforeSigning) {
            sign();
            return;
        }

        if ((!signatureCheckCompleted) || ((signatureCheckReports != null) && !signatureValidationCompleted)) {
            showSignaturesNotValidatedDialog();
            return;
        }

        if (signatureCheckReports == null) {
            sign();
            return;
        }

        for (var signatureId : signatureValidationReports.getSimpleReport().getSignatureIdList()) {
            if (!signatureValidationReports.getSimpleReport().isValid(signatureId)) {
                showSignaturesInvalidDialog();
                return;
            }
        }

        sign();
    }

    public void sign() {
        setActiveStep(3);
        var signingKey = gui.getActiveSigningKey();
        if (signingKey == null) {
            autogram.pickSigningKeyAndThen(key -> {
                gui.setActiveSigningKeyAndThen(key, k -> {
                    gui.disableSigning();
                    getNodeForLoosingFocus().requestFocus();
                    autogram.sign(visualization.getJob(), k);
                });
            });
        } else {
            gui.disableSigning();
            getNodeForLoosingFocus().requestFocus();
            autogram.sign(visualization.getJob(), signingKey);
        }
    }

    public void onChangeKeyButtonPressed(ActionEvent event) {
        gui.resetSigningKey();
        checkExistingSignatureValidityAndSign();
    }

    public void onShowSignaturesButtonPressed(ActionEvent event) {
        if (signaturesController == null)
            signaturesController = new SignaturesController(signatureCheckReports, gui);

        Node root = GUIUtils.loadFXML(signaturesController, "present-signatures-dialog.fxml");
        signaturesController.setMainMenuController(mainMenuController);

        if (mainMenuController != null) {
            mainMenuController.showRightDrawer(root);
            if (signatureValidationCompleted)
                signaturesController.onSignatureValidationCompleted(signatureValidationReports);
        } else {
            var stage = new Stage();
            stage.setTitle("Detailné informácie o podpisoch");
            stage.setScene(new Scene((Parent) root));
            stage.initModality(Modality.WINDOW_MODAL);
            stage.initOwner(mainButton.getScene().getWindow());
            GUIUtils.suppressDefaultFocus(stage, signaturesController);
            stage.show();
            stage.setResizable(false);
            stage.show();

            if (signatureValidationCompleted)
                signaturesController.onSignatureValidationCompleted(signatureValidationReports);
        }
    }

    public void onSignatureCheckCompleted(Reports reports) {
        signatureCheckReports = reports;
        signatureCheckCompleted = true;
        setActiveStep(2);
        if (reports == null) {
            updateSignatureFeedback("Dokument je pripravený na podpis",
                    "Nenašli sa žiadne existujúce podpisy. Skontrolujte zvolený certifikát a môžete pokračovať.",
                    "Bez existujúcich podpisov", "autogram-pill--success");
            removeInlineAlert(ALERT_SIGNATURES_PENDING);
            removeInlineAlert(ALERT_SIGNATURES_INVALID);
            return;
        }
        renderSignatures(reports, false, true);
        updateSignatureFeedback("Kontrola podpisov pokračuje",
                "Dokument už obsahuje podpisy. Autogram teraz dokončuje ich úplnú validáciu.",
                "Podpisy nájdené", "autogram-pill--info");
        showInlineInfoAlert(ALERT_SIGNATURES_PENDING, "Podpisy sa overujú",
                "Dokument obsahuje podpisy. Dokončujem ich validáciu.");

        if (signaturesNotValidatedDialogController != null)
            signaturesNotValidatedDialogController.close();
    }

    public void onSignatureValidationCompleted(Reports reports) {
        signatureValidationCompleted = true;
        signatureValidationReports = reports;
        setActiveStep(2);
        removeInlineAlert(ALERT_SIGNATURES_PENDING);
        renderSignatures(reports, true, SignatureValidator.getInstance().areTLsLoaded());

        if (containsInvalidSignatures(reports)) {
            updateSignatureFeedback("Podpis vyžaduje pozornosť",
                    "Dokument obsahuje neplatné alebo nedôveryhodné podpisy. Pred pokračovaním si pozrite detail podpisov.",
                    "Vyžaduje pozornosť", "autogram-pill--warning");
            showInlineWarningAlert(ALERT_SIGNATURES_INVALID, "Dokument obsahuje neplatné alebo nedôveryhodné podpisy",
                    "Pred podpisom skontrolujte detail podpisov a zvážte, či chcete pokračovať.");
        } else {
            updateSignatureFeedback("Podpisy sú overené",
                    "Existujúce podpisy boli overené. Ak je obsah dokumentu v poriadku, môžete pokračovať v podpise.",
                    "Podpisy overené", "autogram-pill--success");
            removeInlineAlert(ALERT_SIGNATURES_INVALID);
        }

        if (signaturesController != null)
            signaturesController.onSignatureValidationCompleted(reports);

        if (signaturesNotValidatedDialogController != null)
            signaturesNotValidatedDialogController.close();
    }

    public void renderSignatures(Reports reports, boolean isValidated, boolean areTLsLoaded) {
        if (reports == null)
            return;

        signaturesTable.setManaged(true);
        signaturesTable.setVisible(true);
        signaturesTable.getChildren().clear();

        var header = new HBox();
        header.setSpacing(10);
        header.setAlignment(javafx.geometry.Pos.CENTER_LEFT);

        var titleLabel = new Label("Podpisy v dokumente");
        titleLabel.getStyleClass().add("autogram-section-title");

        var badge = new Label(isValidated ? "Overené" : "Zistené podpisy");
        badge.getStyleClass().addAll("autogram-pill", isValidated ? "autogram-pill--success" : "autogram-pill--info");

        header.getChildren().addAll(titleLabel, badge);
        signaturesTable.getChildren().add(header);

        if (!areTLsLoaded)
            signaturesTable.getChildren().add(
                    createWarningText(
                            "Nastala chyba pri sťahovaní dôveryhodných zoznamov a podpisy nie je možné úplne overiť. Skontrolujte si internetové pripojenie."));

        signaturesTable.getChildren().add(
                createSignatureTableRows(reports, isValidated, e -> onShowSignaturesButtonPressed(null), 3));
    }

    public void refreshSigningKey() {
        var key = gui.getActiveSigningKey();
        if (key == null) {
            mainButton.setText("Podpísať dokument");
            changeKeyButton.setVisible(false);
            changeKeyButton.setManaged(false);
            if (activeCertificateLabel != null) {
                activeCertificateLabel.setText("");
                activeCertificateLabel.setVisible(false);
                activeCertificateLabel.setManaged(false);
                activeCertificateLabel.setTooltip(null);
            }
            if (mainMenuController != null) {
                mainMenuController.updateCertificateMetadata("Nevybraný");
            }
        } else {
            var summary = buildSigningKeySummary(key);
            mainButton.setText("Podpísať dokument");
            changeKeyButton.setVisible(true);
            changeKeyButton.setManaged(true);
            if (activeCertificateLabel != null) {
                activeCertificateLabel.setText("Certifikát: " + summary);
                activeCertificateLabel.setVisible(true);
                activeCertificateLabel.setManaged(true);
                activeCertificateLabel.setTooltip(new Tooltip(safeTooltip(summary, key.toString())));
            }
            if (mainMenuController != null) {
                mainMenuController.updateCertificateMetadata(summary);
            }
        }
    }

    public void enableSigning() {
        refreshSigningKey();
        mainButton.setDisable(false);
        changeKeyButton.setDisable(false);
    }

    public void enableSigningOnAllJobs() {
        gui.enableSigningOnAllJobs();
    }

    public void close() {
        if (mainMenuController != null) {
            mainMenuController.showDropZone();
            return;
        }

        var window = mainButton.getScene().getRoot().getScene().getWindow();
        if (window instanceof Stage) {
            ((Stage) window).close();
        }
    }

    public void disableKeyPicking() {
        updateSigningStateText("Načítavam certifikáty",
                "Autogram pripravuje dostupné certifikáty a úložiská. Počkajte prosím chvíľu.");
        mainButton.setText("Načítavam certifikáty…");
        mainButton.setDisable(true);
        changeKeyButton.setDisable(true);
    }

    public void disableSigning() {
        setActiveStep(3);
        updateSigningStateText("Podpisovanie prebieha",
                "Dokument sa práve podpisuje. Po dokončení sa zobrazí výsledok a cieľové umiestnenie súboru.");
        updateBadgeStyle(signatureStateBadge, "autogram-pill--info");
        if (signatureStateBadge != null) {
            signatureStateBadge.setText("Prebieha podpisovanie");
        }
        mainButton.setText("Prebieha podpisovanie…");
        mainButton.setDisable(true);
        changeKeyButton.setDisable(true);
    }

    private void setActiveStep(int stepNumber) {
        if (stepPreviewLabel == null || stepSignaturesLabel == null || stepSigningLabel == null) {
            return;
        }

        var stepLabels = java.util.List.of(stepPreviewLabel, stepSignaturesLabel, stepSigningLabel);
        stepLabels.forEach(label -> label.getStyleClass().remove("autogram-signing-step--active"));

        if (stepNumber >= 1 && stepNumber <= stepLabels.size()) {
            var activeLabel = stepLabels.get(stepNumber - 1);
            if (!activeLabel.getStyleClass().contains("autogram-signing-step--active")) {
                activeLabel.getStyleClass().add("autogram-signing-step--active");
            }
        }
    }

    public void showPlainTextVisualization(String text) {
        plainTextArea.addEventFilter(ContextMenuEvent.CONTEXT_MENU_REQUESTED, Event::consume);
        plainTextArea.setText(text);
        plainTextArea.setVisible(true);
        plainTextArea.setManaged(true);
    }

    public void showHTMLVisualization(String html) {
        webView.setContextMenuEnabled(false);
        webView.getEngine().setJavaScriptEnabled(false);
        var engine = webView.getEngine();
        engine.getLoadWorker().stateProperty().addListener((observable, oldState, newState) -> {
            if (newState == Worker.State.SUCCEEDED) {
                engine.getDocument().getElementById("frame").setAttribute("srcdoc", html);
            }
        });
        engine.load(getClass().getResource("visualization-html.html").toExternalForm());
        webViewContainer.getStyleClass().add("autogram-visualizer-html");
        webViewContainer.setVisible(true);
        webViewContainer.setManaged(true);
    }

    public void showPDFVisualization(ArrayList<byte[]> data) {
        data.forEach(page -> {
            var imgView = new ImageView();
            imgView.fitWidthProperty().bind(pdfVisualizationContainer.widthProperty().subtract(30));
            imgView.setImage(new Image(new ByteArrayInputStream(page)));
            imgView.setPreserveRatio(true);
            imgView.setSmooth(true);

            pdfVisualizationBox.getChildren().add(new HBox(imgView));
        });

        pdfVisualizationContainer.setFitToWidth(true);
        pdfVisualizationContainer.setVisible(true);
        pdfVisualizationContainer.setManaged(true);
    }

    public void showImageVisualization(DSSDocument doc) {
        // TODO what about visualization
        imageVisualization.fitWidthProperty().bind(imageVisualizationContainer.widthProperty().subtract(4));
        imageVisualization.setImage(new Image(doc.openStream()));
        imageVisualization.setPreserveRatio(true);
        imageVisualization.setSmooth(true);
        imageVisualization.setCursor(Cursor.OPEN_HAND);
        imageVisualizationContainer.setPannable(true);
        imageVisualizationContainer.setFitToWidth(true);
        imageVisualizationContainer.setVisible(true);
        imageVisualizationContainer.setManaged(true);
    }

    public void showUnsupportedVisualization() {
        unsupportedVisualizationInfoBox.setVisible(true);
        unsupportedVisualizationInfoBox.setManaged(true);
    }

    public void showPdfaInlineWarning() {
        updateSignatureFeedback("Dokument vyžaduje pozornosť",
                "Dokument nie je vo formáte PDF/A. Ak podpisujete pre úrad, odporúčame skontrolovať jeho akceptovateľnosť.",
                "PDF/A upozornenie", "autogram-pill--warning");
        showInlineWarningAlert(ALERT_PDFA, "Dokument nie je vo formáte PDF/A",
                "Úrady nemusia takýto dokument akceptovať. Upozornenie vypnete v Nastaveniach -> Bezpečnosť -> Kontrola súladu s PDF/A formátom.");
    }

    public void showSigningErrorInline(AutogramException e) {
        var heading = (e != null && e.getHeading() != null && !e.getHeading().isBlank())
                ? e.getHeading()
                : "Podpisovanie zlyhalo";

        String details = "";
        if (e != null) {
            var subheading = e.getSubheading() == null ? "" : e.getSubheading().trim();
            var description = e.getDescription() == null ? "" : e.getDescription().trim();
            details = subheading;
            if (!description.isBlank() && !description.equals(subheading)) {
                details = details.isBlank() ? description : details + " " + description;
            }
        }

        if (details.isBlank()) {
            details = "Skontrolujte certifikát, PIN alebo token a skúste to znova.";
        }

        updateSignatureFeedback("Podpisovanie zlyhalo", details, "Chyba podpisu", "autogram-pill--warning");
        showInlineErrorAlert(ALERT_SIGNING_ERROR, heading, details);
    }

    private boolean containsInvalidSignatures(Reports reports) {
        if (reports == null || reports.getSimpleReport() == null) {
            return false;
        }

        for (var signatureId : reports.getSimpleReport().getSignatureIdList()) {
            if (!reports.getSimpleReport().isValid(signatureId)) {
                return true;
            }
        }
        return false;
    }

    private void showInlineWarningAlert(String key, String title, String message) {
        showInlineAlert(key, title, message, "autogram-inline-alert--warning");
    }

    private void showInlineInfoAlert(String key, String title, String message) {
        showInlineAlert(key, title, message, "autogram-inline-alert--info");
    }

    private void showInlineErrorAlert(String key, String title, String message) {
        showInlineAlert(key, title, message, "autogram-inline-alert--error");
    }

    private void showInlineAlert(String key, String title, String message, String variantStyleClass) {
        if (inlineAlertsBox == null || key == null || key.isBlank()) {
            return;
        }

        var existing = inlineAlerts.get(key);
        if (existing != null) {
            var titleNode = existing.lookup(".autogram-inline-alert__title");
            var bodyNode = existing.lookup(".autogram-inline-alert__body");
            if (titleNode instanceof Label titleLabelNode) {
                titleLabelNode.setText(title);
            }
            if (bodyNode instanceof Label bodyLabelNode) {
                bodyLabelNode.setText(message);
            }
            if (!(titleNode instanceof Label) || !(bodyNode instanceof Label)) {
                removeInlineAlert(key);
                showInlineAlert(key, title, message, variantStyleClass);
            }
            return;
        }

        var card = new VBox();
        card.getStyleClass().addAll("autogram-inline-alert", variantStyleClass);

        var header = new HBox();
        header.getStyleClass().add("autogram-inline-alert__header");

        var icon = new Label("!");
        icon.getStyleClass().add("autogram-inline-alert__icon");

        var titleLabel = new Label(title);
        titleLabel.setWrapText(true);
        titleLabel.getStyleClass().add("autogram-inline-alert__title");

        var spacer = new javafx.scene.layout.Region();
        HBox.setHgrow(spacer, javafx.scene.layout.Priority.ALWAYS);

        var dismissButton = new Button("Skryť");
        dismissButton.getStyleClass().addAll("autogram-link", "autogram-inline-alert__dismiss");
        dismissButton.setOnAction(e -> removeInlineAlert(key));

        header.getChildren().addAll(icon, titleLabel, spacer, dismissButton);

        var bodyLabel = new Label(message);
        bodyLabel.setWrapText(true);
        bodyLabel.getStyleClass().add("autogram-inline-alert__body");

        card.getChildren().addAll(header, bodyLabel);
        inlineAlerts.put(key, card);

        inlineAlertsBox.getChildren().add(card);
        inlineAlertsBox.setManaged(true);
        inlineAlertsBox.setVisible(true);
    }

    private void removeInlineAlert(String key) {
        if (inlineAlertsBox == null) {
            return;
        }

        var alertNode = inlineAlerts.remove(key);
        if (alertNode == null) {
            return;
        }

        inlineAlertsBox.getChildren().remove(alertNode);
        if (inlineAlerts.isEmpty()) {
            inlineAlertsBox.setManaged(false);
            inlineAlertsBox.setVisible(false);
        }
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return mainBox;
    }

    @Override
    public void setPrefWidth(double prefWidth) {
        mainBox.setPrefWidth(prefWidth);
    }

    private String buildSigningKeySummary(digital.slovensko.autogram.core.SigningKey key) {
        try {
            var parsedCn = DSSUtils.parseCN(key.getCertificate().getSubject().getRFC2253());
            if (parsedCn != null && !parsedCn.isBlank()) {
                return parsedCn;
            }
        } catch (RuntimeException ignored) {
            // Fall back to the existing string representation below.
        }

        var fallback = key.toString();
        if (fallback == null || fallback.isBlank()) {
            return "Vybraný certifikát";
        }

        return fallback;
    }

    private String safeTooltip(String summary, String fullValue) {
        if (fullValue == null || fullValue.isBlank() || fullValue.equals(summary)) {
            return summary;
        }

        return summary + "\n" + fullValue;
    }

    private void configureHeader() {
        var document = visualization != null && visualization.getJob() != null ? visualization.getJob().getDocument() : null;
        var mime = document != null && document.getMimeType() != null
                ? document.getMimeType().getMimeTypeString()
                : "Dokument";

        if (documentTypeBadge != null) {
            documentTypeBadge.setText(buildDocumentTypeBadgeText(mime));
        }

        if (shouldCheckValidityBeforeSigning) {
            updateSignatureFeedback("Kontrola dokumentu",
                    "Skontrolujte náhľad dokumentu, existujúce podpisy a zvolený certifikát pred podpisom.",
                    "Kontrola podpisov prebieha", "autogram-pill--info");
        } else {
            updateSignatureFeedback("Dokument pripravený na podpis",
                    "Skontrolujte náhľad dokumentu a zvolený certifikát. Kontrola existujúcich podpisov je vypnutá.",
                    "Kontrola podpisov vypnutá", "autogram-pill--neutral");
        }
    }

    private String buildDocumentTypeBadgeText(String mime) {
        if (mime == null || mime.isBlank()) {
            return "Dokument";
        }

        if (mime.toLowerCase().contains("pdf")) {
            return "PDF dokument";
        }
        if (mime.toLowerCase().contains("xml")) {
            return "XML dokument";
        }
        if (mime.toLowerCase().contains("asice")) {
            return "ASiC kontajner";
        }

        return mime;
    }

    private void updateSignatureFeedback(String stateTitle, String helpText, String badgeText, String badgeStyleClass) {
        updateSigningStateText(stateTitle, helpText);
        if (signatureStateBadge != null) {
            signatureStateBadge.setText(badgeText);
            updateBadgeStyle(signatureStateBadge, badgeStyleClass);
        }
    }

    private void updateSigningStateText(String stateTitle, String helpText) {
        if (signingStateLabel != null && stateTitle != null) {
            signingStateLabel.setText(stateTitle);
        }
        if (headerHelpLabel != null && helpText != null) {
            headerHelpLabel.setText(helpText);
        }
    }

    private void updateBadgeStyle(Label label, String styleClass) {
        if (label == null) {
            return;
        }

        label.getStyleClass().removeAll("autogram-pill--neutral", "autogram-pill--info",
                "autogram-pill--success", "autogram-pill--warning");
        if (styleClass != null && !styleClass.isBlank()) {
            label.getStyleClass().add(styleClass);
        }
    }
}
