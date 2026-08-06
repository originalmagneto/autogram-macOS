package digital.slovensko.autogram.ui.gui;

import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.animation.PauseTransition;
import javafx.application.Platform;
import javafx.scene.control.Button;
import javafx.scene.control.PasswordField;
import javafx.scene.input.KeyCode;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;
import javafx.stage.Stage;
import javafx.util.Duration;

public class PasswordController extends BaseController {
    private final String questionKey;
    private final String errorKey;
    private final String subtitleKey;
    private final boolean isSigningStep;
    private final boolean allowEmpty;
    private Runnable onClose;

    private char[] password;

    @FXML
    PasswordField passwordField;
    @FXML
    Text question;
    @FXML
    Text subtitle;
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

    public PasswordController(String questionKey, String blankPasswordErrorKey, String subtitleKey, boolean isSigningStep, boolean allowEmpty) {
        this.questionKey = questionKey;
        this.errorKey = blankPasswordErrorKey;
        this.subtitleKey = subtitleKey;
        this.isSigningStep = isSigningStep;
        this.allowEmpty = allowEmpty;
    }

    public PasswordController(String questionKey, String blankPasswordErrorKey, boolean isSigningStep, boolean allowEmpty) {
        this(questionKey, blankPasswordErrorKey, null, isSigningStep, allowEmpty);
    }

    @Override
    public void initialize() {
        question.setText(i18n(questionKey));
        error.setText(i18n(errorKey));
        if(subtitleKey != null) {
            subtitle.setText(i18n(subtitleKey));
            subtitle.setManaged(true);
            subtitle.setVisible(true);
        }

        if(isSigningStep) {
            var signLabel = i18n("general.sign.btn");
            mainButton.setText(signLabel.equals("general.sign.btn") ? "Podpísať" : signLabel);
            cancelButton.setManaged(true);
            cancelButton.setVisible(true);
        }

        mainBox.setOnKeyPressed(event -> {
            if (event.getCode() == KeyCode.ESCAPE && cancelButton.isVisible() && !cancelButton.isDisable()) {
                onCancelButtonPressed(null);
                event.consume();
            }
        });

        Platform.runLater(this::focusPasswordFieldForTyping);
        var delayedFocus = new PauseTransition(Duration.millis(220));
        delayedFocus.setOnFinished(event -> focusPasswordFieldForTyping());
        delayedFocus.play();
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
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
            return;
        }

        var window = mainBox.getScene().getRoot().getScene().getWindow();
        if (window instanceof Stage) {
            ((Stage) window).close();
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
