package digital.slovensko.autogram.ui.gui;

import javafx.application.Platform;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.control.TextField;
import javafx.scene.layout.VBox;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Method;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertSame;

class MainMenuControllerOverlayFocusTests {
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
    void findsExplicitAutoFocusSelectorFirst() throws Exception {
        var root = new VBox();
        var button = new Button("B");
        button.setId("targetButton");
        var input = new TextField();
        root.getChildren().addAll(input, button);

        var found = invokeFindOverlayFocusTarget(root, OverlaySpec.defaults().withAutoFocus("#targetButton"));
        assertSame(button, found);
    }

    @Test
    void fallsBackToInputControlWhenSelectorNotProvided() throws Exception {
        var root = new VBox();
        var input = new TextField();
        var button = new Button("B");
        root.getChildren().addAll(button, input);

        var found = invokeFindOverlayFocusTarget(root, OverlaySpec.defaults());
        assertSame(input, found);
    }

    private static Node invokeFindOverlayFocusTarget(VBox root, OverlaySpec spec) throws Exception {
        var result = new AtomicReference<Node>();
        var error = new AtomicReference<Throwable>();
        var done = new CountDownLatch(1);

        Platform.runLater(() -> {
            try {
                var controller = new MainMenuController(null, null);
                Method method = MainMenuController.class
                        .getDeclaredMethod("findOverlayFocusTarget", javafx.scene.Parent.class, OverlaySpec.class);
                method.setAccessible(true);
                result.set((Node) method.invoke(controller, root, spec));
            } catch (Throwable t) {
                error.set(t);
            } finally {
                done.countDown();
            }
        });

        done.await(2, TimeUnit.SECONDS);
        if (error.get() != null) {
            if (error.get() instanceof Exception ex) {
                throw ex;
            }
            throw new RuntimeException(error.get());
        }
        return result.get();
    }
}
