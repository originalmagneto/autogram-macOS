package digital.slovensko.autogram.ui.machine;

import com.sun.jna.Pointer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class MacNativeFileSystemTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void publishesValidatedBytesFromTheRetainedStagingDescriptorDespitePathSwaps() throws Exception {
        var root = temporaryDirectory.toRealPath();
        var parent = Files.createDirectory(root.resolve("target-parent"));
        var replacementParent = root.resolve("replacement-parent");
        var attacker = Files.writeString(root.resolve("replacement-B.pdf"), "replacement-B");
        var nativeFiles = MacNativeFileSystem.createForCurrentPlatform();
        var before = entries(parent);

        var workspace = nativeFiles.createWorkspace(parent);
        var staging = workspace.createStagingFile();
        staging.replaceContent("validated-A".getBytes(StandardCharsets.UTF_8));
        var workspacePath = entries(parent).stream().filter(path -> !before.contains(path)).findFirst().orElseThrow();
        var stagingPath = entries(workspacePath).getFirst();
        Files.delete(stagingPath);
        Files.createLink(stagingPath, attacker);
        Files.move(parent, replacementParent);
        Files.createDirectory(parent);

        workspace.publish(staging, "signed.pdf");

        assertArrayEquals("validated-A".getBytes(StandardCharsets.UTF_8),
                Files.readAllBytes(replacementParent.resolve("signed.pdf")));
        assertFalse(Files.exists(parent.resolve("signed.pdf")));
        assertEquals("replacement-B", Files.readString(attacker));
        assertFalse(workspace.cleanup());
    }

    @Test
    void cleanupDoesNotTraverseAWorkspacePathReplacement() throws Exception {
        var parent = temporaryDirectory.toRealPath();
        var unrelated = Files.createDirectory(parent.resolve("unrelated"));
        var userFile = Files.writeString(unrelated.resolve("keep.txt"), "keep");
        var nativeFiles = MacNativeFileSystem.createForCurrentPlatform();
        var before = entries(parent);
        var workspace = nativeFiles.createWorkspace(parent);
        workspace.createStagingFile().replaceContent("staged".getBytes(StandardCharsets.UTF_8));
        var workspacePath = entries(parent).stream().filter(path -> !before.contains(path)).findFirst().orElseThrow();
        var movedWorkspace = parent.resolve("moved-workspace");
        Files.move(workspacePath, movedWorkspace);
        Files.createSymbolicLink(workspacePath, unrelated);

        var cleaned = workspace.cleanup();

        assertFalse(cleaned);
        assertTrue(Files.isSymbolicLink(workspacePath));
        assertTrue(Files.exists(userFile));
        assertTrue(Files.exists(movedWorkspace));
    }

    @Test
    void failsClosedWhenClonePublicationIsUnsupported() throws Exception {
        var calls = mock(MacNativeFileSystem.NativeCalls.class);
        when(calls.lstat(anyString(), any())).thenAnswer(invocation -> {
            writeIdentity(invocation.getArgument(1), 7, 0040000, 21);
            return 0;
        });
        when(calls.open(anyString(), anyInt())).thenReturn(10);
        when(calls.fstat(anyInt(), any())).thenAnswer(invocation -> {
            writeIdentity(invocation.getArgument(1), 7, 0040000, 21);
            return 0;
        });
        when(calls.mkdirat(anyInt(), anyString(), anyInt())).thenReturn(0);
        when(calls.openat(anyInt(), anyString(), anyInt(), any(Object[].class))).thenReturn(11, 12);
        when(calls.fclonefileat(anyInt(), anyInt(), anyString(), anyInt())).thenReturn(-1);
        var workspace = new MacNativeFileSystem(calls).createWorkspace(Path.of("/private/target"));
        var staging = workspace.createStagingFile();
        com.sun.jna.Native.setLastError(45);
        var failure = assertThrows(MachineProtocolException.class,
                () -> workspace.publish(staging, "signed.pdf"));

        assertEquals("OUTPUT_PUBLISH_UNSUPPORTED", failure.getMessage());
    }

    private static void writeIdentity(Pointer status, int device, int mode, long inode) {
        status.setInt(0, device);
        status.setShort(4, (short) mode);
        status.setLong(8, inode);
    }

    private static java.util.List<Path> entries(Path directory) throws Exception {
        try (var paths = Files.list(directory)) {
            return paths.sorted().toList();
        }
    }
}
