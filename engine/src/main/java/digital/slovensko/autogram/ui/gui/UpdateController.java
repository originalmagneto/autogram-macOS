package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.Updater;
import javafx.application.HostServices;
import javafx.application.Platform;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.scene.Node;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;

public class UpdateController implements SuppressedFocusController {
    private final HostServices hostServices;
    private Updater.UpdateInfo updateInfo;

    @FXML
    Node mainBox;
    @FXML
    Button mainButton;
    @FXML
    Button cancelButton;
    @FXML
    ProgressBar progressBar;
    @FXML
    Text progressText;
    @FXML
    Label versionText;
    @FXML
    Label priorityBadge;
    @FXML
    Label summaryText;
    @FXML
    Label downloadMetaText;
    @FXML
    VBox releaseNotesCard;
    @FXML
    VBox releaseNotesHighlights;

    public UpdateController(HostServices hostServices) {
        this.hostServices = hostServices;
        this.updateInfo = Updater.getUpdateInfo();
    }

    @FXML
    public void initialize() {
        if (updateInfo != null) {
            if (versionText != null) {
                versionText.setText(updateInfo.version);
            }
            if (summaryText != null) {
                summaryText.setText(buildSummaryText(updateInfo));
            }
            if (downloadMetaText != null) {
                var meta = buildDownloadMeta(updateInfo);
                downloadMetaText.setText(meta);
                downloadMetaText.setVisible(!meta.isBlank());
                downloadMetaText.setManaged(!meta.isBlank());
            }
            if (priorityBadge != null) {
                var isSecurityRelease = isSecurityRelease(updateInfo.releaseNotes);
                priorityBadge.setVisible(isSecurityRelease);
                priorityBadge.setManaged(isSecurityRelease);
            }
            if (releaseNotesHighlights != null && releaseNotesCard != null) {
                populateReleaseNoteHighlights(updateInfo.releaseNotes);
            }
        }

        if (progressBar != null) {
            progressBar.setVisible(false);
            progressBar.setManaged(false);
        }
        if (progressText != null) {
            progressText.setVisible(false);
            progressText.setManaged(false);
        }
    }

    public void downloadAction(ActionEvent ignored) {
        if (updateInfo != null && updateInfo.downloadUrl.endsWith(".dmg")) {
            // Start automatic download
            startAutomaticDownload();
        } else {
            // Fallback to web browser
            hostServices.showDocument(Updater.getDownloadUrl());
        }
    }

    private void startAutomaticDownload() {
        // Show progress UI
        if (progressBar != null) {
            progressBar.setVisible(true);
            progressBar.setManaged(true);
            progressBar.setProgress(0);
        }
        if (progressText != null) {
            progressText.setVisible(true);
            progressText.setManaged(true);
            progressText.setText("Sťahovanie...");
        }

        // Disable buttons during download
        mainButton.setDisable(true);
        mainButton.setText("Sťahuje sa...");

        // Start download
        CompletableFuture<Path> downloadFuture = Updater.downloadUpdate(updateInfo, progress -> {
            Platform.runLater(() -> {
                if (progressBar != null) {
                    progressBar.setProgress(progress);
                }
                if (progressText != null) {
                    int percentage = (int) (progress * 100);
                    progressText.setText("Sťahovanie... " + percentage + "%");
                }
            });
        });

        downloadFuture.whenComplete((path, throwable) -> {
            Platform.runLater(() -> {
                if (throwable != null) {
                    // Handle download error
                    showError("Chyba pri sťahovaní: " + throwable.getMessage());
                    resetUI();
                } else {
                    // Download completed successfully
                    if (progressText != null) {
                        progressText.setText("Sťahovanie dokončené!");
                    }
                    mainButton.setText("Otvoriť inštalátor");
                    mainButton.setDisable(false);

                    // Set up install action
                    mainButton.setOnAction(e -> installUpdate(path));
                }
            });
        });
    }

    private Runnable onClose;

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    private void installUpdate(Path updateFile) {
        try {
            Updater.installUpdate(updateFile);
            // Close the dialog after opening the installer
            if (onClose != null) {
                onClose.run();
            } else {
                GUIUtils.closeWindow(mainBox);
            }
        } catch (Exception e) {
            showError("Chyba pri inštalácii: " + e.getMessage());
        }
    }

    private void showError(String message) {
        Alert alert = new Alert(Alert.AlertType.ERROR);
        alert.setTitle("Chyba aktualizácie");
        alert.setHeaderText(null);
        alert.setContentText(message);
        alert.showAndWait();
    }

    private void resetUI() {
        mainButton.setDisable(false);
        mainButton.setText("Stiahnuť novú verziu");
        mainButton.setOnAction(this::downloadAction);

        if (progressBar != null) {
            progressBar.setVisible(false);
            progressBar.setManaged(false);
        }
        if (progressText != null) {
            progressText.setVisible(false);
            progressText.setManaged(false);
        }
    }

    public void onCancelButtonPressed(ActionEvent ignored) {
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

    static boolean isSecurityRelease(String releaseNotes) {
        if (releaseNotes == null || releaseNotes.isBlank()) {
            return false;
        }

        var normalized = releaseNotes.toLowerCase(Locale.ROOT);
        return normalized.contains("security")
                || normalized.contains("warning")
                || normalized.contains("critical")
                || normalized.contains("urgent");
    }

    static List<String> extractReleaseHighlights(String releaseNotes) {
        if (releaseNotes == null || releaseNotes.isBlank()) {
            return List.of("Vylepšenia stability, kompatibility a používateľského zážitku.");
        }

        var highlights = new ArrayList<String>();
        for (var rawLine : releaseNotes.split("\\R")) {
            var normalized = normalizeReleaseLine(rawLine);
            if (normalized.isBlank()) {
                continue;
            }
            if (!highlights.contains(normalized)) {
                highlights.add(normalized);
            }
            if (highlights.size() == 5) {
                break;
            }
        }

        return highlights.isEmpty()
                ? List.of("Podrobnosti o vydaní sú dostupné po otvorení stránky s aktualizáciou.")
                : highlights;
    }

    private void populateReleaseNoteHighlights(String releaseNotes) {
        var highlights = extractReleaseHighlights(releaseNotes);
        releaseNotesHighlights.getChildren().clear();
        for (var highlight : highlights) {
            var label = new Label(highlight);
            label.setWrapText(true);
            label.getStyleClass().add("autogram-update-note");
            releaseNotesHighlights.getChildren().add(label);
        }
        releaseNotesCard.setVisible(true);
        releaseNotesCard.setManaged(true);
    }

    private String buildSummaryText(Updater.UpdateInfo info) {
        if (info == null) {
            return "Je dostupná nová verzia a odporúčame ju nainštalovať.";
        }

        if (isSecurityRelease(info.releaseNotes)) {
            return "Táto aktualizácia obsahuje dôležité bezpečnostné alebo stabilitné opravy. Odporúčame ju nainštalovať čo najskôr.";
        }

        return "Je dostupná nová verzia Autogramu s vylepšeniami stability, kompatibility a používateľského zážitku.";
    }

    private String buildDownloadMeta(Updater.UpdateInfo info) {
        if (info == null) {
            return "";
        }

        var parts = new ArrayList<String>();
        if (info.downloadUrl != null && info.downloadUrl.endsWith(".dmg")) {
            parts.add("Balík pre macOS");
        }
        if (info.fileSize > 0) {
            parts.add(formatFileSize(info.fileSize));
        }
        return String.join(" • ", parts);
    }

    private static String normalizeReleaseLine(String line) {
        if (line == null) {
            return "";
        }

        var normalized = line.trim();
        normalized = normalized.replaceFirst("^[-*+#>\\s]+", "");
        normalized = normalized.replace("`", "");
        normalized = normalized.replaceFirst("(?i)^\\[(warning|security|info)]\\s*", "");
        normalized = normalized.replaceAll("\\s+", " ").trim();
        return normalized;
    }

    private static String formatFileSize(long bytes) {
        if (bytes < 1024) {
            return bytes + " B";
        }
        var units = new String[] { "KB", "MB", "GB" };
        double value = bytes;
        var unitIndex = -1;
        while (value >= 1024 && unitIndex < units.length - 1) {
            value /= 1024;
            unitIndex++;
        }
        return String.format(Locale.US, "%.1f %s", value, units[Math.max(unitIndex, 0)]);
    }
}
