package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.ui.machine.v2.VisibleSignatureAppearance;

public record MachineFile(String id, String source, String target, VisibleSignatureAppearance.Snapshot visibleAppearance) {
    public MachineFile(String id, String source, String target) {
        this(id, source, target, null);
    }
}
