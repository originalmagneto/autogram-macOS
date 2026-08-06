package digital.slovensko.autogram.ui.machine;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonParseException;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;

import java.io.IOException;
import java.io.Reader;

public final class MachineProtocolCodec {
    public static final int VERSION = 1;

    private final Gson gson = new GsonBuilder().disableHtmlEscaping().create();

    public MachineRequest decodeRequest(Reader reader) {
        try {
            var jsonReader = new JsonReader(reader);
            MachineRequest request = gson.fromJson(jsonReader, MachineRequest.class);
            if (request == null || jsonReader.peek() != JsonToken.END_DOCUMENT) {
                throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
            }
            return request;
        } catch (IOException | JsonParseException exception) {
            throw new MachineProtocolException("PROTOCOL_INVALID_REQUEST", exception);
        }
    }

    public String encodeEvent(MachineEvent event) {
        return gson.toJson(event);
    }
}
