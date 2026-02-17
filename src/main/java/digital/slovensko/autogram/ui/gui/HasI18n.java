package digital.slovensko.autogram.ui.gui;

import java.util.ResourceBundle;

public interface HasI18n {
    ResourceBundle getResources();

    default String i18n(String key) {
        if (getResources() == null) {
            return key;
        }

        return getResources().containsKey(key) ? getResources().getString(key) : key;
    }

    default String translate(String key) {
        return i18n(key);
    }

    default String tr(String key) {
        return translate(key);
    }
}
