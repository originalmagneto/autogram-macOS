package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;

public record MachineEvent(
        int protocolVersion,
        String type,
        String sessionId,
        String emittedAt,
        String fileId,
        JsonObject payload) {
}
