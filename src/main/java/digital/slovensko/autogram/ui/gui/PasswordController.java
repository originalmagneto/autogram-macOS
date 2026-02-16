package digital.slovensko.autogram.ui.gui;

import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.application.Platform;
import javafx.animation.PauseTransition;
import javafx.scene.control.Button;
import javafx.scene.control.PasswordField;
import javafx.scene.layout.VBox;
import javafx.scene.input.KeyCode;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.util.Duration;

public class PasswordController {
    private final String questionText;
    private final String errorText;
    private final boolean isSigningStep;
    private final boolean allowEmpty;
    private Runnable onClose;

    private char[] password;

    @FXML
    PasswordField passwordField;
    @FXML
    Text question;
    @FXML
    Text error;
    @FXML
    VBox formGroup;
    @FXML
    Button mainButton;
    @FXML
    Button cancelButton;
    @FXML
    VBox mainBox;

    public PasswordController(String questionText, String blankPasswordErrorText, boolean isSigningStep,
            boolean allowEmpty) {
        this.questionText = questionText;
        this.errorText = blankPasswordErrorText;
        this.isSigningStep = isSigningStep;
        this.allowEmpty = allowEmpty;
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    public void initialize() {
        question.setText(questionText);
        error.setText(errorText);
        if (isSigningStep) {
            mainButton.setText("Podpísať");
            cancelButton.setManaged(true);
            cancelButton.setVisible(true);
        }

        mainBox.setOnKeyPressed(event -> {
            if (event.getCode() == KeyCode.ESCAPE && cancelButton.isVisible() && !cancelButton.isDisable()) {
                onCancelButtonPressed(null);
                event.consume();
            }
        });

        // Allow immediate PIN typing when dialog appears.
        Platform.runLater(() -> {
            focusPasswordFieldForTyping();
        });

        // Re-focus once more after overlay fade-in to avoid focus loss.
        var delayedFocus = new PauseTransition(Duration.millis(220));
        delayedFocus.setOnFinished(event -> {
            focusPasswordFieldForTyping();
        });
        delayedFocus.play();
    }

    public void onPasswordAction() {
        if (passwordField.getText().isEmpty() && !allowEmpty) {
            error.setManaged(true);
            error.setVisible(true);
            formGroup.getStyleClass().add("autogram-form-group--error");
            passwordField.getStyleClass().add("autogram-input--error");

            formGroup.getScene().getWindow().sizeToScene();
            passwordField.requestFocus();
        } else {
            this.password = passwordField.getText().toCharArray();
            if (onClose != null) {
                onClose.run();
            } else {
                GUIUtils.closeWindow(mainBox);
            }
        }
    }

    public void onCancelButtonPressed(ActionEvent event) {
        if (onClose != null) {
            onClose.run();
        } else {
            var window = mainBox.getScene().getRoot().getScene().getWindow();
            if (window instanceof Stage) {
                ((Stage) window).close();
            }
        }
    }

    public char[] getPassword() {
        return password;
    }

    void focusPasswordFieldForTyping() {
        if (passwordField == null) {
            return;
        }

        passwordField.requestFocus();
        passwordField.positionCaret(passwordField.getLength());
    }
}
