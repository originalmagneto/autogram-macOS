package digital.slovensko.autogram.ui.gui;

import javafx.application.Platform;
import javafx.scene.control.Button;
import javafx.scene.control.PasswordField;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PasswordControllerTests {
    @BeforeAll
    static void initFxToolkit() throws InterruptedException {
        try {
            var latch = new CountDownLatch(1);
            Platform.startup(latch::countDown);
            latch.await(2, TimeUnit.SECONDS);
        } catch (IllegalStateException ignored) {
            // Toolkit already initialized.
        }
    }

    @Test
    void signingStepEnablesCancelAndPrimaryLabel() throws InterruptedException {
        var controller = createController(true, false);
        runOnFxThreadAndWait(() -> controller.initialize());

        assertEquals("Podpísať", controller.mainButton.getText());
        assertTrue(controller.cancelButton.isManaged());
        assertTrue(controller.cancelButton.isVisible());
    }

    @Test
    void focusHelperMovesCaretToEnd() throws InterruptedException {
        var controller = createController(false, true);
        controller.passwordField.setText("123456");

        runOnFxThreadAndWait(controller::focusPasswordFieldForTyping);
        assertEquals(6, controller.passwordField.getCaretPosition());
    }

    @Test
    void passwordSubmitStoresPasswordAndInvokesClose() throws InterruptedException {
        var controller = createController(true, false);
        controller.passwordField.setText("9876");
        var onCloseCalled = new AtomicBoolean(false);
        controller.setOnClose(() -> onCloseCalled.set(true));

        runOnFxThreadAndWait(controller::onPasswordAction);

        assertTrue(onCloseCalled.get());
        assertArrayEquals("9876".toCharArray(), controller.getPassword());
    }

    private static PasswordController createController(boolean isSigningStep, boolean allowEmpty) {
        var controller = new PasswordController("Q", "E", isSigningStep, allowEmpty);
        controller.passwordField = new PasswordField();
        controller.question = new Text();
        controller.error = new Text();
        controller.formGroup = new VBox();
        controller.mainButton = new Button("Pokračovať");
        controller.cancelButton = new Button("Zrušiť");
        controller.mainBox = new VBox();
        return controller;
    }

    private static void runOnFxThreadAndWait(Runnable runnable) throws InterruptedException {
        var done = new CountDownLatch(1);
        var error = new AtomicReference<Throwable>();
        Platform.runLater(() -> {
            try {
                runnable.run();
            } catch (Throwable t) {
                error.set(t);
            } finally {
                done.countDown();
            }
        });
        done.await(2, TimeUnit.SECONDS);
        if (error.get() != null) {
            throw new AssertionError(error.get());
        }
    }
}
