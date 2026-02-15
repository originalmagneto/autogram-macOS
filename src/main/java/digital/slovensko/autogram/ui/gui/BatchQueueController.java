package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.Autogram;
import digital.slovensko.autogram.core.Batch;
import digital.slovensko.autogram.core.BatchStartCallback;
import digital.slovensko.autogram.ui.BatchGuiFileResponder;
import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Parent;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.PasswordField;
import javafx.scene.control.ProgressBar;
import javafx.scene.layout.VBox;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class BatchQueueController implements SuppressedFocusController {
    @FXML
    private VBox mainBox;
    @FXML
    private VBox queueContainer;
    @FXML
    private Label queueCountLabel;
    @FXML
    private Label progressLabel;
    @FXML
    private ProgressBar progressBar;
    @FXML
    private VBox progressBarBox;
    @FXML
    private PasswordField pinField;
    @FXML
    private Button signAllButton;
    @FXML
    private Button cancelButton;

    private MainMenuController mainMenuController;
    private Autogram autogram;
    private Batch batch;
    private BatchStartCallback callback;
    private List<File> files;
    private List<QueueItemController> itemControllers = new ArrayList<>();
    private Map<File, QueueItemController> fileToController = new HashMap<>();
    private boolean signingStarted = false;

    public void initialize(MainMenuController mainMenuController, Autogram autogram, Batch batch,
            BatchStartCallback callback) {
        this.mainMenuController = mainMenuController;
        this.autogram = autogram;
        this.batch = batch;
        this.callback = callback;

        // Extract files from responder if possible
        if (callback.getResponder() instanceof BatchGuiFileResponder) {
            this.files = ((BatchGuiFileResponder) callback.getResponder()).getList();
        } else {
            this.files = new ArrayList<>(); // Should not happen in GUI
        }

        queueCountLabel.setText(files.size() + " súborov v poradí");
        progressLabel.setText("Pripravené na podpísanie");
        progressBar.setProgress(0);
        progressBarBox.setVisible(false);
        progressBarBox.setManaged(false);

        loadQueueItems();

        // Select first item by default to show preview
        if (!itemControllers.isEmpty()) {
            selectItem(itemControllers.get(0));
        }
    }

    private void loadQueueItems() {
        queueContainer.getChildren().clear();
        itemControllers.clear();
        fileToController.clear();

        for (File file : files) {
            try {
                FXMLLoader loader = new FXMLLoader(getClass().getResource("batch-queue-item.fxml"));
                Parent itemNode = loader.load();
                QueueItemController controller = loader.getController();
                controller.setFile(file);
                controller.setBatchQueueController(this);

                queueContainer.getChildren().add(itemNode);
                itemControllers.add(controller);
                fileToController.put(file, controller);

                itemNode.setOnMouseClicked(event -> selectItem(controller));
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    public void selectItem(QueueItemController controller) {
        for (QueueItemController item : itemControllers) {
            item.setActive(item == controller);
        }
        mainMenuController.showFilePreview(controller.getFile());
    }

    public void updateStatus(File file, String status, String styleClass) {
        Platform.runLater(() -> {
            QueueItemController controller = fileToController.get(file);
            if (controller != null) {
                controller.setStatus(status, styleClass);
            }
            updateProgress();
        });
    }

    private void updateProgress() {
        if (batch == null)
            return;

        int processed = batch.getProcessedDocumentsCount();
        int total = batch.getTotalNumberOfDocuments();

        progressLabel.setText(processed + " / " + total + " podpísaných");
        progressBar.setProgress(total > 0 ? (double) processed / total : 0);

        if (processed >= total && signingStarted) {
            // Batch is complete — the result dialog is handled by GUI.onDocumentBatchSaved
            onSigningComplete();
        }
    }

    public void update() {
        // Called by GUI.updateBatch() on each document completion
        Platform.runLater(this::updateProgress);
    }

    @FXML
    private void onSignAllAction() {
        var signingKey = mainMenuController.getGui().getActiveSigningKey();
        if (signingKey == null) {
            autogram.pickSigningKeyAndThen(key -> {
                mainMenuController.getGui().setActiveSigningKeyAndThen(key, k -> {
                    startSigning(k);
                });
            });
        } else {
            startSigning(signingKey);
        }
    }

    private void startSigning(digital.slovensko.autogram.core.SigningKey key) {
        signingStarted = true;

        // Update UI to show signing state
        signAllButton.setText("Podpisujem...");
        signAllButton.setDisable(true);
        pinField.setDisable(true);
        cancelButton.setText("Zastaviť");

        // Show progress bar
        progressBarBox.setVisible(true);
        progressBarBox.setManaged(true);
        progressBar.setProgress(0);
        progressLabel.setText("0 / " + files.size() + " podpísaných");

        // Cache PIN if user entered one
        String pin = pinField.getText();
        if (pin != null && !pin.isEmpty()) {
            mainMenuController.getGui().setBatchPin(pin.toCharArray());
        }

        mainMenuController.getGui().onWorkThreadDo(() -> {
            try {
                callback.accept(key);
            } finally {
                mainMenuController.getGui().clearBatchPin();
            }
        });
    }

    private void onSigningComplete() {
        Platform.runLater(() -> {
            signAllButton.setText("Hotovo ✓");
            signAllButton.setDisable(true);
            cancelButton.setText("Zavrieť");
            cancelButton.setOnAction(e -> {
                mainMenuController.hideRightDrawer();
                mainMenuController.showDropZone();
            });
        });
    }

    public void onBatchEnded() {
        Platform.runLater(() -> {
            mainMenuController.hideRightDrawer();
            mainMenuController.showDropZone();
        });
    }

    @FXML
    private void onCancelAction() {
        if (signingStarted) {
            // If signing is in progress, end the batch
            batch.end();
        } else {
            callback.cancel();
        }
        mainMenuController.hideRightDrawer();
        mainMenuController.showDropZone();
    }

    @Override
    public javafx.scene.Node getNodeForLoosingFocus() {
        return pinField;
    }
}
