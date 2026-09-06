package digital.slovensko.autogram.core.settings;

import java.util.Locale;

public class Country {

    private String name;

    private String shortname;

    public Country(String name, String shrotname) {
        this.name = name;
        this.shortname = shrotname;
    }

    public String getName() {
        return name;
    }

    // Compatibility bridge with upstream API where country name is locale-aware.
    public String getName(Locale inLocale) {
        return getName();
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getShortname() {
        return shortname;
    }

    public void setShortname(String shrotname) {
        this.shortname = shrotname;
    }
}
