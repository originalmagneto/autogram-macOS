package digital.slovensko.autogram.ui.gui;

import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.scene.control.Label;
import javafx.scene.layout.HBox;
import javafx.scene.shape.SVGPath;
import java.io.File;

public class QueueItemController {
    @FXML
    private HBox mainBox;
    @FXML
    private Label fileNameLabel;
    @FXML
    private Label statusLabel;
    @FXML
    private SVGPath statusIcon;

    private BatchQueueController batchQueueController;
    private File file;

    public void setFile(File file) {
        this.file = file;
        fileNameLabel.setText(file.getName());
    }

    public File getFile() {
        return file;
    }

    public void setBatchQueueController(BatchQueueController controller) {
        this.batchQueueController = controller;
    }

    public void setActive(boolean active) {
        if (active) {
            if (!mainBox.getStyleClass().contains("autogram-batch-item--active")) {
                mainBox.getStyleClass().add("autogram-batch-item--active");
            }
        } else {
            mainBox.getStyleClass().remove("autogram-batch-item--active");
        }
    }

    public void setStatus(String status, String styleClass) {
        Platform.runLater(() -> {
            statusLabel.setText(status);
            mainBox.getStyleClass().removeAll("autogram-batch-item--success", "autogram-batch-item--error");
            if (styleClass != null) {
                mainBox.getStyleClass().add(styleClass);
            }

            // Update icon Based on status
            if ("autogram-batch-item--success".equals(styleClass)) {
                statusIcon.setContent("M5 13l4 4L19 7"); // Checkmark
            } else if ("autogram-batch-item--error".equals(styleClass)) {
                statusIcon.setContent("M18 6L6 18M6 6l12 12"); // X
            }
        });
    }
}
