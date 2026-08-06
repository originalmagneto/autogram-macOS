package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;

public record MachineRequest(
        int protocolVersion,
        String requestId,
        MachineOperation operation,
        JsonObject payload) {
}
