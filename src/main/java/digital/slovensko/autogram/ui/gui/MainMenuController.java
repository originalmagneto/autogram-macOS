package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.Autogram;
import digital.slovensko.autogram.core.SigningJob;
import digital.slovensko.autogram.core.UserSettings;
import digital.slovensko.autogram.core.errors.AutogramException;
import digital.slovensko.autogram.core.errors.EmptyDirectorySelectedException;
import digital.slovensko.autogram.core.errors.NoFilesSelectedException;
import digital.slovensko.autogram.core.errors.UnrecognizedException;
import digital.slovensko.autogram.ui.BatchGuiFileResponder;
import digital.slovensko.autogram.ui.SaveFileResponder;
import digital.slovensko.autogram.util.macos.MacOSNotification;
import javafx.animation.FadeTransition;
import javafx.animation.Interpolator;
import javafx.animation.PauseTransition;
import javafx.animation.TranslateTransition;
import javafx.application.Platform;
import javafx.event.ActionEvent;
import javafx.event.EventHandler;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.control.TextInputControl;
import javafx.scene.control.*;
import javafx.scene.effect.GaussianBlur;
import javafx.scene.input.*;
import javafx.scene.layout.Region;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBox;
import javafx.stage.FileChooser;
import javafx.stage.Stage;
import javafx.stage.Window;
import javafx.util.Duration;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

public class MainMenuController extends BaseController implements SuppressedFocusController {
    private final Autogram autogram;
    private final UserSettings userSettings;
    private GUI gui;

    @FXML
    VBox dropZone;

    @FXML
    MenuBar menuBar;

    @FXML
    SplitPane splitPane;

    @FXML
    VBox sidebar;

    @FXML
    StackPane contentArea;

    @FXML
    VBox dropZonePanel;

    @FXML
    VBox signingPanel;

    @FXML
    VBox successPanel;

    @FXML
    VBox settingsPanel;

    @FXML
    StackPane dialogOverlay;

    @FXML
    VBox dialogContentHost;
    @FXML
    VBox dialogContainer;

    @FXML
    Label statusLabel;

    @FXML
    Button navDropZone;

    @FXML
    Button navSettings;

    @FXML
    Button navAbout;

    @FXML
    VBox metadataPanel;

    @FXML
    Label metaFilename;

    @FXML
    Label metaSize;

    @FXML
    Label metaPages;

    @FXML
    Label metaFormat;

    @FXML
    Label metaCertificate;

    @FXML
    TitledPane existingSignaturesPane;

    @FXML
    VBox existingSignaturesList;

    @FXML
    VBox rightDrawer;
    @FXML
    StackPane rightDrawerContent;
    private VBox lastPrimaryPanel;

    public MainMenuController(Autogram autogram, UserSettings userSettings) {
        this.autogram = autogram;
        this.userSettings = userSettings;
    }

    public void setGui(GUI gui) {
        this.gui = gui;
    }

    public GUI getGui() {
        return gui;
    }

    @FXML
    public void initialize() {
        if (menuBar != null) {
            menuBar.useSystemMenuBarProperty().set(true);
        }
        lastPrimaryPanel = dropZonePanel;

        // Enhanced keyboard navigation
        dropZone.setFocusTraversable(true);
        dropZone.setOnKeyPressed(event -> {
            if (event.getCode().toString().equals("SPACE") || event.getCode().toString().equals("ENTER")) {
                onUploadButtonAction();
                event.consume();
            }
        });

        // Initialize SplitPane with right drawer hidden
        hideRightDrawer();

        dropZone.setOnDragOver(event -> {
            if (event.getDragboard().hasFiles()) {
                event.acceptTransferModes(TransferMode.COPY);
                if (!dropZone.getStyleClass().contains("autogram-dropzone-active")) {
                    dropZone.getStyleClass().add("autogram-dropzone-active");
                }
            }
            event.consume();
        });

        dropZone.setOnDragEntered(event -> {
            dropZone.getStyleClass().add("autogram-dropzone--entered");
        });

        dropZone.setOnDragExited(event -> {
            dropZone.getStyleClass().remove("autogram-dropzone-active");
            dropZone.getStyleClass().removeIf(style -> style.equals("autogram-dropzone--entered"));
            event.consume();
        });

        dropZone.setOnDragDropped(event -> {
            var dragboard = event.getDragboard();
            boolean success = false;

            if (dragboard.hasFiles()) {
                var files = dragboard.getFiles();
                try {
                    onFilesSelected(files);
                    success = true;
                } catch (Exception e) {
                    // Handle file processing errors gracefully
                    System.err.println("Error processing dropped files: " + e.getMessage());
                    autogram.onSigningFailed(new UnrecognizedException(e));
                }
            }

            // Remove active styling
            dropZone.getStyleClass().remove("autogram-dropzone-active");

            event.setDropCompleted(success);
            event.consume();
        });

    }

    public void onHideRightDrawer(ActionEvent event) {
        hideRightDrawer();
    }

    public void showRightDrawer(Node content) {
        Platform.runLater(() -> {
            boolean alreadyVisible = rightDrawer.isVisible();
            rightDrawerContent.getChildren().clear();
            rightDrawerContent.getChildren().add(content);
            rightDrawer.setMinWidth(320);
            rightDrawer.setPrefWidth(500);
            rightDrawer.setMaxWidth(800);
            rightDrawer.setManaged(true);
            rightDrawer.setVisible(true);

            // Calculate divider position based on SplitPane width
            double splitPaneWidth = splitPane.getWidth();
            double drawerWidth = 500.0;

            if (!alreadyVisible) {
                // Slide-in animation: start off-screen to the right
                rightDrawer.setTranslateX(drawerWidth);
                rightDrawer.setOpacity(0);

                // Expand the window width
                var stage = (Stage) splitPane.getScene().getWindow();
                if (stage != null) {
                    double currentStageWidth = stage.getWidth();
                    rightDrawer.setManaged(true);
                    rightDrawer.setVisible(true);
                    stage.setWidth(currentStageWidth + drawerWidth);

                    double newSplitPaneWidth = splitPaneWidth + drawerWidth;
                    double targetRatio = splitPaneWidth / newSplitPaneWidth;
                    if (targetRatio < 0.2)
                        targetRatio = 0.2;
                    splitPane.setDividerPosition(1, targetRatio);
                }

                // Animate slide-in from right
                TranslateTransition slide = new TranslateTransition(Duration.millis(200), rightDrawer);
                slide.setFromX(drawerWidth);
                slide.setToX(0);
                slide.setInterpolator(Interpolator.EASE_OUT);
                slide.play();

                FadeTransition fade = new FadeTransition(Duration.millis(200), rightDrawer);
                fade.setFromValue(0);
                fade.setToValue(1);
                fade.play();
            } else {
                rightDrawer.setManaged(true);
                rightDrawer.setVisible(true);
                splitPane.setDividerPosition(1, Math.max(0.2, 1.0 - (rightDrawer.getPrefWidth() / Math.max(1, splitPane.getWidth()))));
            }
        });
    }

    public void hideRightDrawer() {
        Platform.runLater(() -> {
            if (rightDrawer.isVisible()) {
                double currentDrawerWidth = rightDrawer.getWidth();
                if (currentDrawerWidth <= 0)
                    currentDrawerWidth = 500.0;

                var stage = (Stage) splitPane.getScene().getWindow();
                if (stage != null) {
                    var targetWidth = Math.max(stage.getMinWidth(), stage.getWidth() - currentDrawerWidth);
                    stage.setWidth(targetWidth);
                }
            }
            rightDrawer.setMinWidth(0);
            rightDrawer.setPrefWidth(0);
            rightDrawer.setMaxWidth(0);
            rightDrawer.setVisible(false);
            rightDrawer.setManaged(false);
            if (splitPane != null && splitPane.getDividers().size() > 1) {
                splitPane.setDividerPosition(1, 1.0);
            }
        });
    }

    // ========== Content Panel Management ==========

    /**
     * Show a specific content panel in the right area, hiding all others.
     */
    private void showPanel(VBox panel) {
        // Hide all panels except the target
        for (VBox p : new VBox[] { dropZonePanel, signingPanel, successPanel, settingsPanel }) {
            if (p != panel) {
                p.setVisible(false);
                p.setManaged(false);
            }
        }

        // Fade in the target panel
        panel.setOpacity(0);
        panel.setVisible(true);
        panel.setManaged(true);
        FadeTransition fadeIn = new FadeTransition(Duration.millis(150), panel);
        fadeIn.setFromValue(0);
        fadeIn.setToValue(1);
        fadeIn.setInterpolator(Interpolator.EASE_BOTH);
        fadeIn.play();

        if (panel != settingsPanel) {
            lastPrimaryPanel = panel;
        }

        // Hide metadata if back to drop zone or in settings, show if in signing/success
        if (panel == dropZonePanel || panel == settingsPanel) {
            metadataPanel.setVisible(false);
            metadataPanel.setManaged(false);

            // Highlight nav items
            if (panel == dropZonePanel) {
                navDropZone.getStyleClass().add("autogram-sidebar-item--active");
                navSettings.getStyleClass().remove("autogram-sidebar-item--active");
                navAbout.getStyleClass().remove("autogram-sidebar-item--active");
            } else if (panel == settingsPanel) {
                navSettings.getStyleClass().add("autogram-sidebar-item--active");
                navDropZone.getStyleClass().remove("autogram-sidebar-item--active");
                navAbout.getStyleClass().remove("autogram-sidebar-item--active");
            }
        } else {
            metadataPanel.setVisible(true);
            metadataPanel.setManaged(true);
        }
    }

    /**
     * Update the metadata panel with document information.
     */
    public void updateMetadata(String filename, String size, String pages, String format, String certificate) {
        Platform.runLater(() -> {
            metaFilename.setText(filename);
            metaSize.setText(size);
            metaPages.setText(pages);
            metaFormat.setText(format);
            metaCertificate.setText(certificate);
            metadataPanel.setVisible(true);
            metadataPanel.setManaged(true);
        });
    }

    /**
     * Update only the certificate field in the metadata panel.
     */
    public void updateCertificateMetadata(String certificate) {
        Platform.runLater(() -> {
            metaCertificate.setText(certificate);
        });
    }

    /**
     * Update only the format field in the metadata panel.
     */
    /**
     * Update only the format field in the metadata panel.
     */
    public void updateFormatMetadata(String format) {
        Platform.runLater(() -> {
            metaFormat.setText(format);
        });
    }

    /**
     * Update the list of existing signatures in the sidebar.
     */
    public void updateExistingSignatures(List<String> signatures) {
        Platform.runLater(() -> {
            existingSignaturesList.getChildren().clear();
            if (signatures == null || signatures.isEmpty()) {
                existingSignaturesPane.setVisible(false);
                existingSignaturesPane.setManaged(false);
            } else {
                for (String sig : signatures) {
                    Label label = new Label(sig);
                    label.getStyleClass().add("autogram-metadata-value");
                    label.setWrapText(true);
                    existingSignaturesList.getChildren().add(label);
                }
                existingSignaturesPane.setVisible(true);
                existingSignaturesPane.setManaged(true);
            }
        });
    }

    /**
     * Show the drop zone (default view).
     */
    public void showDropZone() {
        Platform.runLater(() -> {
            showPanel(dropZonePanel);
            setStatus("Pripravený");
            updateNavActive(navDropZone);
        });
    }

    /**
     * Show signing visualization content in the right pane.
     * 
     * @param content The loaded FXML content from signing-dialog.fxml
     */
    public void showSigningContent(Parent content) {
        Platform.runLater(() -> {
            signingPanel.getChildren().clear();
            signingPanel.getChildren().add(content);
            VBox.setVgrow(content, javafx.scene.layout.Priority.ALWAYS);
            showPanel(signingPanel);
            setStatus("Podpisovanie...");
        });
    }

    /**
     * Show preview/visualization for a specific file without starting signing.
     */
    public void showFilePreview(File file) {
        Platform.runLater(() -> {
            try {
                var job = SigningJob.buildFromFile(file, null, userSettings.isPdfaCompliance(),
                        userSettings.getSignatureLevel(), userSettings.isEn319132(), null,
                        userSettings.isPlainXmlEnabled());

                var visualization = digital.slovensko.autogram.core.visualization.DocumentVisualizationBuilder.fromJob(
                        job,
                        userSettings);
                var title = "Náhľad: " + file.getName();
                var controller = new SigningDialogController(visualization, autogram, gui, title,
                        userSettings.isSignaturesValidity());
                controller.setMainMenuController(this);

                var root = GUIUtils.loadFXML(controller, "signing-dialog.fxml");
                signingPanel.getChildren().clear();
                signingPanel.getChildren().add(root);
                VBox.setVgrow(root, javafx.scene.layout.Priority.ALWAYS);
                showPanel(signingPanel);

                // Update metadata for this file
                String filename = file.getName();
                String size = formatFileSize(file);
                String pages = formatPageCount(file);
                String format = job.getDocument().getMimeType().getMimeTypeString();
                String cert = gui.getActiveSigningKey() != null ? gui.getActiveSigningKey().toString() : "Nevybraný";
                updateMetadata(filename, size, pages, format, cert);

                // Trigger signature check
                autogram.getUI().onWorkThreadDo(() -> autogram.checkAndValidateSignatures(job));
            } catch (Exception e) {
                e.printStackTrace();
            }
        });
    }

    private String formatFileSize(File file) {
        long bytes = file.length();
        if (bytes < 1024)
            return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        char pre = "KMGTPE".charAt(exp - 1);
        return String.format("%.1f %sB", bytes / Math.pow(1024, exp), pre);
    }

    private String formatPageCount(File file) {
        // Simple heuristic or use PDFUtils if it's a PDF
        if (file.getName().toLowerCase().endsWith(".pdf")) {
            var doc = new eu.europa.esig.dss.model.FileDocument(file);
            return String.valueOf(digital.slovensko.autogram.util.PDFUtils.getPageCount(doc));
        }
        return "N/A";
    }

    /**
     * Show success content in the right pane.
     * 
     * @param content The loaded FXML content from signing-success-dialog.fxml
     */
    public void showSuccessContent(Parent content) {
        Platform.runLater(() -> {
            successPanel.getChildren().clear();
            successPanel.getChildren().add(content);
            showPanel(successPanel);
            setStatus("Podpísané ✓");
        });
    }

    /**
     * Show a dialog integrated within the main window as an overlay.
     */
    @FXML
    StackPane contentPanelContainer;

    private FadeTransition activeOverlayTransition;
    private OverlaySpec activeOverlaySpec = OverlaySpec.defaults();
    private Parent activeOverlayContent;
    private final EventHandler<KeyEvent> overlayKeyHandler = this::onOverlayKeyPressed;

    /**
     * Show a dialog integrated within the main window as an overlay.
     */
    public void showOverlayDialog(Parent content) {
        showOverlayDialog(content, OverlaySpec.defaults());
    }

    /**
     * Show a dialog integrated within the main window as an overlay.
     */
    public void showOverlayDialog(Parent content, OverlaySpec spec) {
        Platform.runLater(() -> {
            // Cancel any active transition to prevent race conditions (e.g. hiding clearing
            // content)
            if (activeOverlayTransition != null) {
                activeOverlayTransition.stop();
            }

            dialogContentHost.getChildren().clear();
            dialogContentHost.getChildren().add(content);
            activeOverlaySpec = spec != null ? spec : OverlaySpec.defaults();
            activeOverlayContent = content;
            if (dialogContainer != null) {
                dialogContainer.setMaxSize(Region.USE_COMPUTED_SIZE, Region.USE_COMPUTED_SIZE);
                dialogContainer.setPrefSize(Region.USE_COMPUTED_SIZE, Region.USE_COMPUTED_SIZE);
                applyDialogSizePreset(activeOverlaySpec.sizePreset());
            }
            dialogOverlay.setOpacity(0);
            dialogOverlay.setVisible(true);
            dialogOverlay.setManaged(true);
            dialogOverlay.toFront();

            // Apply subtle blur to background content only
            if (contentPanelContainer != null) {
                contentPanelContainer.setEffect(new GaussianBlur(3));
            } else {
                // Fallback if container is missing (shouldn't happen with updated FXML)
                contentArea.setEffect(new GaussianBlur(3));
            }

            // Fade in the overlay
            activeOverlayTransition = new FadeTransition(Duration.millis(150), dialogOverlay);
            activeOverlayTransition.setFromValue(0);
            activeOverlayTransition.setToValue(1);
            activeOverlayTransition.setInterpolator(Interpolator.EASE_BOTH);
            activeOverlayTransition.play();

            // Keep dialog sized by its content to avoid oversized empty cards.
            VBox.setVgrow(content, javafx.scene.layout.Priority.NEVER);
            installOverlayKeyboardHandler();
            requestOverlayInputFocus(content, activeOverlaySpec);
        });
    }

    private void applyDialogSizePreset(OverlaySizePreset sizePreset) {
        dialogContainer.getStyleClass()
                .removeAll("autogram-overlay-card--compact", "autogram-overlay-card--default", "autogram-overlay-card--wide");
        var styleClass = switch (sizePreset) {
            case COMPACT -> "autogram-overlay-card--compact";
            case WIDE -> "autogram-overlay-card--wide";
            case DEFAULT -> "autogram-overlay-card--default";
        };
        dialogContainer.getStyleClass().add(styleClass);

        dialogContainer.setMinSize(Region.USE_PREF_SIZE, Region.USE_PREF_SIZE);
        dialogContainer.setPrefSize(Region.USE_COMPUTED_SIZE, Region.USE_COMPUTED_SIZE);

        switch (sizePreset) {
            case COMPACT -> {
                dialogContainer.setMaxWidth(400);
                dialogContainer.setMaxHeight(Region.USE_PREF_SIZE);
            }
            case WIDE -> {
                dialogContainer.setMaxWidth(680);
                dialogContainer.setMaxHeight(Region.USE_PREF_SIZE);
            }
            case DEFAULT -> {
                dialogContainer.setMaxWidth(540);
                dialogContainer.setMaxHeight(Region.USE_PREF_SIZE);
            }
        }
    }

    private void installOverlayKeyboardHandler() {
        dialogOverlay.removeEventFilter(KeyEvent.KEY_PRESSED, overlayKeyHandler);
        dialogOverlay.addEventFilter(KeyEvent.KEY_PRESSED, overlayKeyHandler);
    }

    private void onOverlayKeyPressed(KeyEvent event) {
        if (!dialogOverlay.isVisible() || activeOverlayContent == null) {
            return;
        }

        if (event.getCode() == KeyCode.ESCAPE && activeOverlaySpec.closeOnEscape()) {
            if (!fireOverlayCancelAction()) {
                hideOverlayDialog();
            }
            event.consume();
            return;
        }

        if (event.getCode() == KeyCode.TAB && activeOverlaySpec.trapFocus()) {
            trapOverlayFocus(event);
        }
    }

    private boolean fireOverlayCancelAction() {
        var selector = activeOverlaySpec.cancelActionSelector();
        if (selector == null || selector.isBlank() || activeOverlayContent == null) {
            return false;
        }

        var target = activeOverlayContent.lookup(selector);
        if (target instanceof ButtonBase buttonBase && !buttonBase.isDisable()) {
            buttonBase.fire();
            return true;
        }

        return false;
    }

    private void trapOverlayFocus(KeyEvent event) {
        if (activeOverlayContent == null || dialogOverlay.getScene() == null) {
            return;
        }

        var focusableNodes = collectFocusableNodes(activeOverlayContent);
        if (focusableNodes.isEmpty()) {
            return;
        }

        var currentFocusOwner = dialogOverlay.getScene().getFocusOwner();
        var currentIndex = focusableNodes.indexOf(currentFocusOwner);
        final int nextIndex;
        if (event.isShiftDown()) {
            nextIndex = currentIndex <= 0 ? focusableNodes.size() - 1 : currentIndex - 1;
        } else {
            nextIndex = currentIndex < 0 || currentIndex == focusableNodes.size() - 1 ? 0 : currentIndex + 1;
        }

        focusableNodes.get(nextIndex).requestFocus();
        event.consume();
    }

    private List<Node> collectFocusableNodes(Node root) {
        var focusableNodes = new ArrayList<Node>();
        collectFocusableNodesRecursive(root, focusableNodes);
        return focusableNodes;
    }

    private void collectFocusableNodesRecursive(Node node, List<Node> focusableNodes) {
        if (node == null || !node.isVisible() || !node.isManaged() || node.isDisable()) {
            return;
        }

        if (node.isFocusTraversable()) {
            focusableNodes.add(node);
        }

        if (node instanceof Parent parent) {
            for (var child : parent.getChildrenUnmodifiable()) {
                collectFocusableNodesRecursive(child, focusableNodes);
            }
        }
    }

    private void requestOverlayInputFocus(Parent content, OverlaySpec spec) {
        var focusTarget = findOverlayFocusTarget(content, spec);
        if (focusTarget == null) {
            return;
        }

        focusNode(focusTarget);

        var delayedFocus = new PauseTransition(Duration.millis(170));
        delayedFocus.setOnFinished(event -> focusNode(focusTarget));
        delayedFocus.play();
    }

    private Node findOverlayFocusTarget(Parent content, OverlaySpec spec) {
        if (spec.autoFocusSelector() != null && !spec.autoFocusSelector().isBlank()) {
            var selectedNode = content.lookup(spec.autoFocusSelector());
            if (selectedNode != null) {
                return selectedNode;
            }
        }

        for (var selector : List.of(".password-field", ".text-field", ".choice-box", ".radio-button", ".button")) {
            var selectedNode = content.lookup(selector);
            if (selectedNode != null) {
                return selectedNode;
            }
        }

        var focusableNodes = collectFocusableNodes(content);
        return focusableNodes.isEmpty() ? null : focusableNodes.get(0);
    }

    private void focusNode(Node target) {
        target.requestFocus();
        if (target instanceof TextInputControl inputControl) {
            inputControl.positionCaret(inputControl.getLength());
        }
    }

    /**
     * Hide the integrated dialog overlay.
     */
    public void hideOverlayDialog() {
        Platform.runLater(() -> {
            // Cancel any active transition
            if (activeOverlayTransition != null) {
                activeOverlayTransition.stop();
            }

            // Fade out the overlay
            activeOverlayTransition = new FadeTransition(Duration.millis(120), dialogOverlay);
            activeOverlayTransition.setFromValue(1);
            activeOverlayTransition.setToValue(0);
            activeOverlayTransition.setInterpolator(Interpolator.EASE_BOTH);
            activeOverlayTransition.setOnFinished(e -> {
                dialogOverlay.setVisible(false);
                dialogOverlay.setManaged(false);
                dialogContentHost.getChildren().clear();
                dialogOverlay.removeEventFilter(KeyEvent.KEY_PRESSED, overlayKeyHandler);
                activeOverlayContent = null;
                activeOverlaySpec = OverlaySpec.defaults();
            });
            activeOverlayTransition.play();

            // Remove blur from background
            if (contentPanelContainer != null) {
                contentPanelContainer.setEffect(null);
            } else {
                contentArea.setEffect(null);
            }
        });
    }

    /**
     * Set the status text in the sidebar footer.
     */
    public void setStatus(String text) {
        Platform.runLater(() -> {
            if (statusLabel != null) {
                statusLabel.setText(text);
            }
        });
    }

    /**
     * Update which sidebar nav item appears active.
     */
    private void updateNavActive(Button activeButton) {
        navDropZone.getStyleClass().removeIf(s -> s.equals("autogram-sidebar-item--active"));
        if (activeButton != null) {
            if (!activeButton.getStyleClass().contains("autogram-sidebar-item--active")) {
                activeButton.getStyleClass().add("autogram-sidebar-item--active");
            }
        }
    }

    // ========== Navigation Handlers ==========

    @FXML
    public void onNavDropZone() {
        if (settingsPanel != null
                && settingsPanel.isVisible()
                && lastPrimaryPanel != null
                && lastPrimaryPanel != dropZonePanel) {
            showPanel(lastPrimaryPanel);
            if (lastPrimaryPanel == signingPanel) {
                setStatus("Podpisovanie...");
            } else if (lastPrimaryPanel == successPanel) {
                setStatus("Podpísané ✓");
            } else {
                setStatus("Pripravený");
            }
            updateNavActive(navDropZone);
            return;
        }

        showDropZone();
    }

    // ========== File Handling ==========

    public void onUploadButtonAction() {
        var chooser = new FileChooser();
        Window owner = dropZone != null && dropZone.getScene() != null ? dropZone.getScene().getWindow() : null;
        var list = chooser.showOpenMultipleDialog(owner);

        try {
            onFilesSelected(list);
        } catch (Exception e) {
            autogram.onSigningFailed(new UnrecognizedException(e));
        }
    }

    public void onFilesSelected(List<File> list) {
        hideRightDrawer();
        if (list == null)
            return;

        try {
            if (list.size() == 0)
                throw new NoFilesSelectedException();

            var dirsList = list.stream().filter(f -> f.isDirectory()).toList();
            var filesList = list.stream().filter(f -> f.isFile()).toList();

            if (dirsList.size() == 1 && filesList.size() == 0)
                signDirectory(dirsList.get(0));

            if (dirsList.size() == 0 && filesList.size() > 0)
                signFiles(list);

            if (dirsList.size() > 1)
                throw new AutogramException("MULTIPLE_FOLDERS");

            if (dirsList.size() > 0 && filesList.size() > 0)
                throw new AutogramException("MIXED_FILE_TYPES");

        } catch (AutogramException e) {
            autogram.onSigningFailed(e);
        }
    }

    private List<File> getFilesList(List<File> list) {
        var filesList = list.stream().filter(f -> f.isFile()).toList();
        if (filesList.size() == 0)
            throw new NoFilesSelectedException();

        return filesList;
    }

    private void signFiles(List<File> list) {
        // send null tspSource if signature shouldn't be timestamped
        var tspSource = userSettings.getTsaEnabled() ? userSettings.getTspSource() : null;

        var filesList = getFilesList(list);
        if (filesList.size() == 1) {
            var file = filesList.get(0);
            var job = SigningJob.buildFromFile(file,
                    new SaveFileResponder(file, autogram, userSettings.shouldSignPDFAsPades()),
                    userSettings.isPdfaCompliance(), userSettings.getSignatureLevel(), userSettings.isEn319132(),
                    tspSource, userSettings.isPlainXmlEnabled());
            autogram.sign(job);
        } else {
            autogram.batchStart(filesList.size(), new BatchGuiFileResponder(autogram, filesList,
                    filesList.get(0).toPath().getParent().resolve("signed"), userSettings.isPdfaCompliance(),
                    userSettings.getSignatureLevel(), userSettings.shouldSignPDFAsPades(), userSettings.isEn319132(),
                    tspSource, userSettings.isPlainXmlEnabled()));
        }
    }

    private void signDirectory(File dir) {
        var directoryArray = dir.listFiles();
        if (directoryArray == null || directoryArray.length == 0)
            throw new EmptyDirectorySelectedException(dir.getAbsolutePath());
        var directoryFiles = List.of(directoryArray);

        var filesList = getFilesList(directoryFiles);
        var targetDirectoryName = dir.getName() + "_signed";
        var targetDirectory = dir.toPath().getParent().resolve(targetDirectoryName);

        // send null tspSource if signature shouldn't be timestamped
        var tspSource = userSettings.getTsaEnabled() ? userSettings.getTspSource() : null;

        autogram.batchStart(filesList.size(),
                new BatchGuiFileResponder(autogram, filesList, targetDirectory, userSettings.isPdfaCompliance(),
                        userSettings.getSignatureLevel(), userSettings.shouldSignPDFAsPades(),
                        userSettings.isEn319132(), tspSource, userSettings.isPlainXmlEnabled()));
    }

    public void onAboutButtonAction() {
        autogram.onAboutInfo();
    }

    @FXML
    public void onSettingButtonAction() {
        var controller = new SettingsDialogController(userSettings);
        controller.setMainMenuController(this);
        controller.setOnSave(() -> {
            MacOSNotification.notify("Autogram", "Nastavenia boli uložené");
            // If they changed the trusted list or validator settings, we might need to
            // refresh
            autogram.initializeSignatureValidator(gui.scheduledExecutorService, gui.cachedExecutorService,
                    userSettings.getTrustedList());
        });
        controller.setOnReset(this::onSettingButtonAction);
        var root = GUIUtils.loadFXML(controller, "settings-dialog.fxml");

        settingsPanel.getChildren().clear();
        settingsPanel.getChildren().add(root);
        showPanel(settingsPanel);
    }

    @FXML
    public void onCheckUpdateButtonAction() {
        autogram.checkForUpdate();
    }

    @FXML
    public void onQuitButtonAction() {
        Platform.exit();
    }

    @Override
    public Node getNodeForLoosingFocus() {
        return dropZone;
    }
}
