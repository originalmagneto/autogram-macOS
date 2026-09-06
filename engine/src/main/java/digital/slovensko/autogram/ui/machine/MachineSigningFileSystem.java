package digital.slovensko.autogram.ui.machine;

import java.io.IOException;
import java.nio.file.Path;

interface MachineSigningFileSystem {
    RetainedFile openSource(Path source) throws IOException;

    Workspace createWorkspace(Path targetParent) throws IOException;

    interface RetainedFile extends AutoCloseable {
        byte[] readAll() throws IOException;

        void replaceContent(byte[] content) throws IOException;

        @Override
        void close() throws IOException;
    }

    interface Workspace extends AutoCloseable {
        RetainedFile createStagingFile() throws IOException;

        void publish(RetainedFile source, String targetLeaf) throws IOException;

        boolean cleanup();

        @Override
        void close() throws IOException;
    }
}
