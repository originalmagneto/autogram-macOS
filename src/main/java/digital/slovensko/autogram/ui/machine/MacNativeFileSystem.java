package digital.slovensko.autogram.ui.machine;

import com.sun.jna.Library;
import com.sun.jna.Memory;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.UUID;

/**
 * Descriptor-relative file operations for the Apple silicon machine signer.
 * Constants and signatures are from the macOS SDK headers sys/fcntl.h,
 * sys/stat.h, sys/unistd.h, and sys/clonefile.h.
 */
final class MacNativeFileSystem implements MachineSigningFileSystem {
    private static final int O_RDONLY = 0x0000;
    private static final int O_RDWR = 0x0002;
    private static final int O_NOFOLLOW = 0x00000100;
    private static final int O_CREAT = 0x00000200;
    private static final int O_EXCL = 0x00000800;
    private static final int O_DIRECTORY = 0x00100000;
    private static final int O_CLOEXEC = 0x01000000;
    private static final int AT_REMOVEDIR = 0x0080;
    private static final int AT_SYMLINK_NOFOLLOW = 0x0020;
    private static final int SEEK_SET = 0;
    private static final int MODE_PRIVATE_DIRECTORY = 0700;
    private static final int MODE_PRIVATE_FILE = 0600;
    private static final int S_IFMT = 0170000;
    private static final int S_IFREG = 0100000;
    private static final int S_IFDIR = 0040000;
    private static final int EEXIST = 17;
    private static final int ENOTSUP = 45;
    private static final int STAT_SIZE_ARM64 = 144;

    private final NativeCalls calls;

    MacNativeFileSystem(NativeCalls calls) {
        this.calls = Objects.requireNonNull(calls);
    }

    static MacNativeFileSystem createForCurrentPlatform() {
        var os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
        var architecture = System.getProperty("os.arch", "").toLowerCase(Locale.ROOT);
        var version = System.getProperty("os.version", "");
        requireSupportedPlatform(os, architecture, version);
        return new MacNativeFileSystem(Native.load(Platform.C_LIBRARY_NAME, NativeCalls.class));
    }

    static void requireSupportedPlatform(String os, String architecture, String version) {
        if (!os.contains("mac") || !(architecture.equals("aarch64") || architecture.equals("arm64"))
                || platformMajorVersion(version) < 27) {
            throw new MachineProtocolException("MACHINE_PLATFORM_UNSUPPORTED");
        }
    }

    private static int platformMajorVersion(String version) {
        try {
            return Integer.parseInt(version.split("\\.", 2)[0]);
        } catch (RuntimeException exception) {
            return -1;
        }
    }

    @Override
    public RetainedFile openSource(Path source) throws IOException {
        return openStable(source, S_IFREG);
    }

    @Override
    public PrivateWorkspace createWorkspace(Path targetParent) throws IOException {
        var parent = openStable(targetParent, S_IFDIR);
        String workspaceLeaf = ".autogram-machine-" + UUID.randomUUID();
        boolean directoryCreated = false;
        try {
            check(calls.mkdirat(parent.descriptor(), workspaceLeaf, MODE_PRIVATE_DIRECTORY), "mkdirat");
            directoryCreated = true;
            int descriptor = checkDescriptor(calls.openat(parent.descriptor(), workspaceLeaf,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, 0), "openat workspace");
            return new PrivateWorkspace(calls, parent, workspaceLeaf, new RetainedFile(calls, descriptor, false));
        } catch (Throwable failure) {
            boolean cleaned = true;
            if (directoryCreated) {
                try {
                    cleaned = calls.unlinkat(parent.descriptor(), workspaceLeaf, AT_REMOVEDIR) == 0;
                } catch (Throwable cleanupFailure) {
                    cleaned = false;
                }
            }
            cleaned &= parent.closeSafely();
            if (!cleaned) {
                throw new MachineProtocolException("OUTPUT_CLEANUP_FAILED", failure);
            }
            throw rethrow(failure);
        }
    }

    private RetainedFile openStable(Path path, int expectedType) throws IOException {
        var before = identityAtPath(path);
        int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC;
        if (expectedType == S_IFDIR) {
            flags |= O_DIRECTORY;
        }
        int descriptor = checkDescriptor(calls.open(path.toString(), flags), "open");
        var retained = new RetainedFile(calls, descriptor, true);
        try {
            var after = identityAtDescriptor(descriptor);
            if (!before.sameObject(after) || (after.mode() & S_IFMT) != expectedType) {
                throw new IOException("File identity changed during open");
            }
            return retained;
        } catch (Throwable failure) {
            if (!retained.closeSafely()) {
                throw new MachineProtocolException("OUTPUT_CLEANUP_FAILED", failure);
            }
            throw rethrow(failure);
        }
    }

    private NativeIdentity identityAtPath(Path path) throws IOException {
        try (var status = new Memory(STAT_SIZE_ARM64)) {
            check(calls.lstat(path.toString(), status), "lstat");
            return NativeIdentity.read(status);
        }
    }

    private NativeIdentity identityAtDescriptor(int descriptor) throws IOException {
        try (var status = new Memory(STAT_SIZE_ARM64)) {
            check(calls.fstat(descriptor, status), "fstat");
            return NativeIdentity.read(status);
        }
    }

    private static int checkDescriptor(int result, String operation) throws NativeIOException {
        if (result < 0) {
            throw nativeFailure(operation);
        }
        return result;
    }

    private static void check(int result, String operation) throws NativeIOException {
        if (result != 0) {
            throw nativeFailure(operation);
        }
    }

    private static NativeIOException nativeFailure(String operation) {
        return new NativeIOException(operation, Native.getLastError());
    }

    private static IOException rethrow(Throwable failure) throws IOException {
        if (failure instanceof IOException exception) {
            throw exception;
        }
        if (failure instanceof RuntimeException exception) {
            throw exception;
        }
        if (failure instanceof Error error) {
            throw error;
        }
        return new IOException(failure);
    }

    interface NativeCalls extends Library {
        int open(String path, int flags);

        int openat(int directoryDescriptor, String path, int flags, Object... mode);

        int mkdirat(int directoryDescriptor, String path, int mode);

        int unlinkat(int directoryDescriptor, String path, int flags);

        int fclonefileat(int sourceDescriptor, int destinationDirectoryDescriptor, String destination, int flags);

        int lstat(String path, Pointer status);

        int fstat(int descriptor, Pointer status);

        int fstatat(int directoryDescriptor, String path, Pointer status, int flags);

        long read(int descriptor, byte[] buffer, long count);

        long write(int descriptor, Pointer buffer, long count);

        long lseek(int descriptor, long offset, int whence);

        int ftruncate(int descriptor, long length);

        int fsync(int descriptor);

        int close(int descriptor);
    }

    static final class RetainedFile implements MachineSigningFileSystem.RetainedFile {
        private final NativeCalls calls;
        private final int descriptor;
        private final boolean readOnly;
        private boolean closed;

        private RetainedFile(NativeCalls calls, int descriptor, boolean readOnly) {
            this.calls = calls;
            this.descriptor = descriptor;
            this.readOnly = readOnly;
        }

        @Override
        public byte[] readAll() throws IOException {
            requireOpen();
            if (calls.lseek(descriptor, 0, SEEK_SET) < 0) {
                throw nativeFailure("lseek");
            }
            var output = new ByteArrayOutputStream();
            var buffer = new byte[8192];
            while (true) {
                long count = calls.read(descriptor, buffer, buffer.length);
                if (count < 0) {
                    throw nativeFailure("read");
                }
                if (count == 0) {
                    return output.toByteArray();
                }
                output.write(buffer, 0, Math.toIntExact(count));
            }
        }

        @Override
        public void replaceContent(byte[] content) throws IOException {
            requireOpen();
            if (readOnly) {
                throw new IOException("Descriptor is read only");
            }
            check(calls.ftruncate(descriptor, 0), "ftruncate");
            if (calls.lseek(descriptor, 0, SEEK_SET) < 0) {
                throw nativeFailure("lseek");
            }
            if (content.length > 0) {
                try (var nativeContent = new Memory(content.length)) {
                    nativeContent.write(0, content, 0, content.length);
                    long offset = 0;
                    while (offset < content.length) {
                        long written = calls.write(descriptor, nativeContent.share(offset), content.length - offset);
                        if (written <= 0) {
                            throw nativeFailure("write");
                        }
                        offset += written;
                    }
                }
            }
            check(calls.fsync(descriptor), "fsync");
        }

        int descriptor() {
            requireOpen();
            return descriptor;
        }

        private void requireOpen() {
            if (closed) {
                throw new IllegalStateException("Descriptor is closed");
            }
        }

        boolean closeSafely() {
            if (closed) {
                return true;
            }
            closed = true;
            try {
                return calls.close(descriptor) == 0;
            } catch (Throwable failure) {
                return false;
            }
        }

        private boolean matchesDirectoryEntry(RetainedFile directory, String name) {
            try {
                return identity().sameObject(directoryEntryIdentity(directory, name));
            } catch (Throwable failure) {
                return false;
            }
        }

        private NativeIdentity identity() throws IOException {
            try (var status = new Memory(STAT_SIZE_ARM64)) {
                check(calls.fstat(descriptor, status), "fstat");
                return NativeIdentity.read(status);
            }
        }

        private NativeIdentity directoryEntryIdentity(RetainedFile directory, String name) throws IOException {
            try (var status = new Memory(STAT_SIZE_ARM64)) {
                check(calls.fstatat(directory.descriptor(), name, status, AT_SYMLINK_NOFOLLOW), "fstatat");
                return NativeIdentity.read(status);
            }
        }

        @Override
        public void close() throws IOException {
            if (!closeSafely()) {
                throw nativeFailure("close");
            }
        }
    }

    static final class PrivateWorkspace implements MachineSigningFileSystem.Workspace {
        private final NativeCalls calls;
        private final RetainedFile parent;
        private final String workspaceLeaf;
        private final RetainedFile directory;
        private final List<OwnedLeaf> leaves = new ArrayList<>();
        private boolean cleaned;

        private PrivateWorkspace(NativeCalls calls, RetainedFile parent, String workspaceLeaf, RetainedFile directory) {
            this.calls = calls;
            this.parent = parent;
            this.workspaceLeaf = workspaceLeaf;
            this.directory = directory;
        }

        @Override
        public RetainedFile createStagingFile() throws IOException {
            requireOpen();
            var leaf = "signed-" + UUID.randomUUID() + ".pdf";
            int descriptor = checkDescriptor(calls.openat(directory.descriptor(), leaf,
                    O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, MODE_PRIVATE_FILE), "openat staging");
            var file = new RetainedFile(calls, descriptor, false);
            leaves.add(new OwnedLeaf(leaf, file));
            return file;
        }

        @Override
        public void publish(MachineSigningFileSystem.RetainedFile source, String targetLeaf) throws IOException {
            requireOpen();
            if (targetLeaf.isBlank() || targetLeaf.contains("/")) {
                throw new IOException("Invalid target leaf");
            }
            if (!(source instanceof RetainedFile retainedSource)) {
                throw new IOException("Source descriptor is not native");
            }
            // fclonefileat atomically creates a non-existing destination leaf from the retained source fd.
            int result = calls.fclonefileat(retainedSource.descriptor(), parent.descriptor(), targetLeaf, 0);
            if (result != 0) {
                int error = Native.getLastError();
                if (error == ENOTSUP) {
                    throw new MachineProtocolException("OUTPUT_PUBLISH_UNSUPPORTED");
                }
                if (error == EEXIST) {
                    throw new MachineProtocolException("OUTPUT_TARGET_EXISTS");
                }
                throw new NativeIOException("fclonefileat", error);
            }
            check(calls.fsync(parent.descriptor()), "fsync target parent");
        }

        @Override
        public boolean cleanup() {
            if (cleaned) {
                return true;
            }
            boolean success = true;
            for (var leaf : leaves) {
                if (!leaf.file().matchesDirectoryEntry(directory, leaf.name())) {
                    success = false;
                } else {
                    try {
                        success &= calls.unlinkat(directory.descriptor(), leaf.name(), 0) == 0;
                    } catch (Throwable failure) {
                        success = false;
                    }
                }
                success &= leaf.file().closeSafely();
            }
            success &= directory.closeSafely();
            try {
                success &= calls.unlinkat(parent.descriptor(), workspaceLeaf, AT_REMOVEDIR) == 0;
            } catch (Throwable failure) {
                success = false;
            }
            success &= parent.closeSafely();
            cleaned = success;
            return success;
        }

        private void requireOpen() {
            if (cleaned) {
                throw new IllegalStateException("Workspace is closed");
            }
        }

        @Override
        public void close() throws IOException {
            if (!cleanup()) {
                throw new MachineProtocolException("OUTPUT_CLEANUP_FAILED");
            }
        }
    }

    private record OwnedLeaf(String name, RetainedFile file) {
    }

    private record NativeIdentity(int device, int mode, long inode) {
        private static NativeIdentity read(Pointer status) {
            // Darwin arm64 struct stat starts with dev_t, mode_t, nlink_t, and ino64_t at these SDK offsets.
            return new NativeIdentity(status.getInt(0), Short.toUnsignedInt(status.getShort(4)), status.getLong(8));
        }

        private boolean sameObject(NativeIdentity other) {
            return device == other.device && inode == other.inode;
        }
    }

    private static final class NativeIOException extends IOException {
        private NativeIOException(String operation, int error) {
            super(operation + " failed");
        }
    }
}
