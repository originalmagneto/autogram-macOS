package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.drivers.TokenDriver;
import javafx.fxml.FXML;
import javafx.scene.control.RadioButton;
import javafx.scene.control.ToggleGroup;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;

import java.util.List;
import java.util.function.Consumer;

public class PickDriverDialogController {
    private final Consumer<TokenDriver> callback;
    private final List<? extends TokenDriver> drivers;

    @FXML
    VBox formGroup;
    @FXML
    Text error;
    @FXML
    VBox radios;
    @FXML
    VBox mainBox;
    private ToggleGroup toggleGroup;
    private Runnable onClose;

    public PickDriverDialogController(List<? extends TokenDriver> drivers, Consumer<TokenDriver> callback) {
        this.drivers = drivers;
        this.callback = callback;
    }

    public void initialize() {
        toggleGroup = new ToggleGroup();
        for (TokenDriver driver : drivers) {
            var radioButton = new RadioButton(driver.getName());
            radioButton.setToggleGroup(toggleGroup);
            radioButton.setUserData(driver);
            radios.getChildren().add(radioButton);
        }
    }

    public void setOnClose(Runnable onClose) {
        this.onClose = onClose;
    }

    private Runnable onCancel;

    public void setOnCancel(Runnable onCancel) {
        this.onCancel = onCancel;
    }

    public void onCancelButtonAction() {
        if (onCancel != null) {
            onCancel.run();
        }

        if (onClose != null) {
            onClose.run();
        } else {
            GUIUtils.closeWindow(mainBox);
        }
    }

    public void onPickDriverButtonAction() {
        if (toggleGroup.getSelectedToggle() == null) {
            error.setManaged(true);
            error.setVisible(true);
            formGroup.getStyleClass().add("autogram-form-group--error");
        } else {
            if (onClose != null) {
                onClose.run();
            } else {
                GUIUtils.closeWindow(mainBox);
            }
            var driver = (TokenDriver) toggleGroup.getSelectedToggle().getUserData();
            callback.accept(driver);
        }
    }
}
