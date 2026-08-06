package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;

public record MachineError(String code, String messageKey, String fallbackMessage, boolean retryable, String recovery) {
    public JsonObject toPayload() {
        var payload = new JsonObject();
        payload.addProperty("code", code);
        payload.addProperty("messageKey", messageKey);
        payload.addProperty("fallbackMessage", fallbackMessage);
        payload.addProperty("retryable", retryable);
        payload.addProperty("recovery", recovery);
        return payload;
    }
}
