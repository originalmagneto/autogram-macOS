package digital.slovensko.autogram.ui.gui;

public record OverlaySpec(
        OverlaySizePreset sizePreset,
        String autoFocusSelector,
        String cancelActionSelector,
        boolean closeOnEscape,
        boolean trapFocus) {

    public OverlaySpec {
        if (sizePreset == null) {
            sizePreset = OverlaySizePreset.DEFAULT;
        }
    }

    public static OverlaySpec defaults() {
        return new OverlaySpec(OverlaySizePreset.DEFAULT, null, null, false, true);
    }

    public static OverlaySpec compact() {
        return defaults().withSizePreset(OverlaySizePreset.COMPACT);
    }

    public static OverlaySpec wide() {
        return defaults().withSizePreset(OverlaySizePreset.WIDE);
    }

    public OverlaySpec withSizePreset(OverlaySizePreset value) {
        return new OverlaySpec(value, autoFocusSelector, cancelActionSelector, closeOnEscape, trapFocus);
    }

    public OverlaySpec withAutoFocus(String value) {
        return new OverlaySpec(sizePreset, value, cancelActionSelector, closeOnEscape, trapFocus);
    }

    public OverlaySpec withCancelAction(String value) {
        return new OverlaySpec(sizePreset, autoFocusSelector, value, closeOnEscape, trapFocus);
    }

    public OverlaySpec withCloseOnEscape(boolean value) {
        return new OverlaySpec(sizePreset, autoFocusSelector, cancelActionSelector, value, trapFocus);
    }

    public OverlaySpec withTrapFocus(boolean value) {
        return new OverlaySpec(sizePreset, autoFocusSelector, cancelActionSelector, closeOnEscape, value);
    }
}
