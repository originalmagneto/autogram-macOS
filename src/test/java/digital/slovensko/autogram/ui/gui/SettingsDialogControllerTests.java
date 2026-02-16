package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.UserSettings;
import javafx.application.Platform;
import javafx.scene.control.Button;
import javafx.scene.control.ScrollPane;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SettingsDialogControllerTests {
    @BeforeAll
    static void initFxToolkit() throws InterruptedException {
        try {
            var latch = new CountDownLatch(1);
            Platform.startup(latch::countDown);
            latch.await(2, TimeUnit.SECONDS);
        } catch (IllegalStateException ignored) {
            // Toolkit already initialized by another test.
        }
    }

    @Test
    void showPanelMarksOnlySelectedSettingsTabAsVisibleAndActive() throws Exception {
        var controller = new SettingsDialogController(UserSettings.load());

        var signingPanel = new ScrollPane();
        var validationPanel = new ScrollPane();
        var securityPanel = new ScrollPane();
        var otherPanel = new ScrollPane();

        var signingButton = new Button();
        var validationButton = new Button();
        var securityButton = new Button();
        var otherButton = new Button();

        signingButton.getStyleClass().add("autogram-tab-item--active");

        setField(controller, "signingSettingsContent", signingPanel);
        setField(controller, "validationSettingsContent", validationPanel);
        setField(controller, "securitySettingsContent", securityPanel);
        setField(controller, "otherSettingsContent", otherPanel);
        setField(controller, "signingNavButton", signingButton);
        setField(controller, "validationNavButton", validationButton);
        setField(controller, "securityNavButton", securityButton);
        setField(controller, "otherNavButton", otherButton);

        Method showPanelMethod = SettingsDialogController.class.getDeclaredMethod("showPanel", ScrollPane.class,
                Button.class);
        showPanelMethod.setAccessible(true);
        showPanelMethod.invoke(controller, validationPanel, validationButton);

        assertFalse(signingPanel.isVisible());
        assertFalse(signingPanel.isManaged());
        assertTrue(validationPanel.isVisible());
        assertTrue(validationPanel.isManaged());
        assertFalse(securityPanel.isVisible());
        assertFalse(otherPanel.isVisible());

        assertFalse(signingButton.getStyleClass().contains("autogram-tab-item--active"));
        assertTrue(validationButton.getStyleClass().contains("autogram-tab-item--active"));
    }

    private static void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = SettingsDialogController.class.getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
