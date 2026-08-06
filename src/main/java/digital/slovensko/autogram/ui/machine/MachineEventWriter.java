package digital.slovensko.autogram.ui.machine;

import com.google.gson.JsonObject;

import java.io.PrintWriter;
import java.time.Instant;

public final class MachineEventWriter {
    private final MachineProtocolCodec codec;
    private final PrintWriter output;

    public MachineEventWriter(PrintWriter output) {
        this.codec = new MachineProtocolCodec();
        this.output = output;
    }

    public synchronized void write(String type, String sessionId, String fileId, JsonObject payload) {
        var event = new MachineEvent(MachineProtocolCodec.VERSION, type, sessionId, Instant.now().toString(), fileId,
                payload == null ? new JsonObject() : payload);
        output.print(codec.encodeEvent(event));
        output.print('\n');
        output.flush();
    }

    public synchronized void writeTerminal(String type, String sessionId, JsonObject payload) {
        write(type, sessionId, null, payload);
        output.flush();
    }
}
