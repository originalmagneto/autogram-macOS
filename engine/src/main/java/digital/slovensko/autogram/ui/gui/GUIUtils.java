package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.UserSettings;
import digital.slovensko.autogram.core.errors.AutogramException;
import digital.slovensko.autogram.util.OperatingSystem;
import javafx.application.Platform;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.scene.image.Image;
import javafx.stage.Modality;
import javafx.stage.Stage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.ResourceBundle;

public class GUIUtils {
    private static final Logger logger = LoggerFactory.getLogger(GUIUtils.class);
    private static Image appIcon;

    /**
     * Set the Autogram app icon on a stage for consistent dock/taskbar branding.
     */
    public static void setAppIcon(Stage stage) {
        if (appIcon == null) {
            byte[] iconBytes = null;
            try (var is = GUIUtils.class.getResourceAsStream("Autogram.png")) {
                if (is != null) {
                    iconBytes = is.readAllBytes();
                    appIcon = new Image(new java.io.ByteArrayInputStream(iconBytes));
                }
            } catch (IOException e) {
                logger.debug("Failed to load icon bytes", e);
            }

            if (iconBytes != null) {
                // Also set for macOS Dock if possible
                try {
                    // Ensure AWT Toolkit is initialized
                    java.awt.Toolkit.getDefaultToolkit();

                    if (Taskbar.isTaskbarSupported()) {
                        var taskbar = Taskbar.getTaskbar();
                        if (taskbar.isSupported(Taskbar.Feature.ICON_IMAGE)) {
                            BufferedImage awtImage = ImageIO.read(new java.io.ByteArrayInputStream(iconBytes));
                            if (awtImage != null) {
                                taskbar.setIconImage(awtImage);
                                logger.info("Successfully set taskbar icon via AWT Taskbar");
                            } else {
                                logger.warn("AWT ImageIO.read returned null for icon");
                            }
                        } else {
                            logger.info("Taskbar.Feature.ICON_IMAGE is not supported");
                        }
                    } else {
                        logger.info("Taskbar is not supported on this platform");
                    }
                } catch (Exception e) {
                    logger.debug("Failed to set taskbar icon", e);
                }
            } else {
                logger.warn("Autogram.png not found in resources");
            }
        }
        if (appIcon != null && OperatingSystem.current() != OperatingSystem.MAC) {
            stage.getIcons().add(appIcon);
        }
    }

    static Parent loadFXML(Object controller, String fxml) {
        try {
            var loader = new FXMLLoader();
            loader.setLocation(controller.getClass().getResource(fxml));
            loader.setController(controller);
            var language = UserSettings.load().getLanguageLocale();
            loader.setResources(ResourceBundle.getBundle("digital.slovensko.autogram.ui.gui.language.l10n", language));
            return loader.load();
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    static void showOnTop(Stage stage) {
        stage.requestFocus();
        stage.setAlwaysOnTop(true);
        stage.toFront();
        stage.show();

        new Thread(() -> {
            try {
                Thread.sleep(42);
            } catch (InterruptedException ignored) {
                // noop
            }

            Platform.runLater(() -> stage.setAlwaysOnTop(false));
        }).start();
    }

    public static void suppressDefaultFocus(Stage stage, SuppressedFocusController controller) {
        stage.focusedProperty().addListener(((observable, old, isFocused) -> {
            if (isFocused)
                controller.getNodeForLoosingFocus().requestFocus(); // everything else looses focus
        }));
    }

    public static void closeWindow(Node node) {
        ((Stage) node.getScene().getWindow()).close();
    }

    public static void startIconified(Stage stage) {
        if (OperatingSystem.current() == OperatingSystem.LINUX) {
            stage.setIconified(true);
            stage.setOnShown((e) -> Platform.runLater(() -> {
                // hack to force relayout because Ubuntu shows a blank scene for an unknown
                // reason
                // see https://github.com/openjdk/jfx/pull/1733
                stage.setWidth(stage.getWidth());
            }));

        } else {
            // WINDOWS & MAC need to set iconified after showing the primary stage,
            // otherwise it starts blank
            stage.setOpacity(0); // prevents startup blink
            stage.setOnShown((e) -> Platform.runLater(() -> {
                stage.setIconified(true);
                stage.setOpacity(1);
            }));
        }
    }

    public static String exceptionToString(Exception exception) {
        var writer = new StringWriter();
        var printWriter = new PrintWriter(writer);
        exception.printStackTrace(printWriter);
        printWriter.flush();
        printWriter.close();

        return writer.toString();
    }

    public static void hackToForceRelayout(Stage stage) {
        // this MUST be run after stage was shown to work on all platforms
        var w = stage.getScene().getWindow();
        // This forces layout recalculation and fixes issue
        // https://github.com/slovensko-digital/autogram/issues/172
        w.setHeight(w.getHeight() - 1);
    }

    public static void showError(AutogramException e, String buttonI18nKey, boolean wait) {
        showError(e, buttonI18nKey, wait, false);
    }

    public static void showError(AutogramException e, String buttonI18nKey, boolean wait, boolean errorDetailsDisabled) {
        logger.debug("GUI showing error", e);
        var controller = new ErrorController(e, errorDetailsDisabled);
        var root = GUIUtils.loadFXML(controller, "error-dialog.fxml");
        controller.setMainButtonText(buttonI18nKey);

        var stage = new Stage();
        GUIUtils.setAppIcon(stage);
        stage.setTitle(e.getHeading());
        stage.setScene(new Scene(root));

        stage.sizeToScene();
        stage.setResizable(false);
        stage.initModality(Modality.APPLICATION_MODAL);

        GUIUtils.suppressDefaultFocus(stage, controller);

        if (wait) {
            stage.showAndWait();
        } else {
            stage.show();
        }
    }
}
