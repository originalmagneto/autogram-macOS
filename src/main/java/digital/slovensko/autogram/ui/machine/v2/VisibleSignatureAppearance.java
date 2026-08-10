package digital.slovensko.autogram.ui.machine.v2;

import digital.slovensko.autogram.ui.machine.MachineProtocolException;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;

public record VisibleSignatureAppearance(
        String renderedPngPath, int page, float originX, float originY,
        float width, float height, Instant signingTime) {

    public Snapshot snapshot() {
        var path = strictPath(renderedPngPath);
        if (page <= 0 || !Float.isFinite(originX) || !Float.isFinite(originY)
                || !Float.isFinite(width) || !Float.isFinite(height) || width <= 0 || height <= 0
                || signingTime == null) {
            throw invalid();
        }
        try {
            if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS) || !path.toRealPath(LinkOption.NOFOLLOW_LINKS).equals(path)) {
                throw invalid();
            }
            byte[] bytes;
            try (var input = FileChannel.open(path, StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)) {
                bytes = readAll(input);
            }
            if (!isPng(bytes)) {
                throw invalid();
            }
            return new Snapshot(this, bytes);
        } catch (IOException exception) {
            throw invalid(exception);
        }
    }

    private static Path strictPath(String value) {
        try {
            var path = Path.of(value);
            if (!path.isAbsolute() || !path.equals(path.normalize()) || path.getNameCount() == 0) {
                throw invalid();
            }
            return path;
        } catch (RuntimeException exception) {
            if (exception instanceof MachineProtocolException protocolException) {
                throw protocolException;
            }
            throw invalid(exception);
        }
    }

    private static boolean isPng(byte[] bytes) {
        return bytes.length >= 8 && bytes[0] == (byte) 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E
                && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A;
    }

    private static byte[] readAll(FileChannel input) throws IOException {
        var output = new ByteArrayOutputStream();
        var buffer = ByteBuffer.allocate(8192);
        while (input.read(buffer) != -1) {
            buffer.flip();
            output.write(buffer.array(), 0, buffer.remaining());
            buffer.clear();
        }
        return output.toByteArray();
    }

    private static MachineProtocolException invalid() {
        return new MachineProtocolException("PROTOCOL_INVALID_REQUEST");
    }

    private static MachineProtocolException invalid(Throwable cause) {
        return new MachineProtocolException("PROTOCOL_INVALID_REQUEST", cause);
    }

    public record Snapshot(VisibleSignatureAppearance appearance, byte[] pngBytes) {
        public Snapshot {
            pngBytes = pngBytes.clone();
        }

        @Override
        public byte[] pngBytes() {
            return pngBytes.clone();
        }
    }
}
