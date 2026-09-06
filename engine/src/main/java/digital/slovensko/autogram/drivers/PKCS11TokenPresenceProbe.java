package digital.slovensko.autogram.drivers;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.file.Path;
import java.util.Optional;

final class PKCS11TokenPresenceProbe {
    private static final long CKR_OK = 0L;
    private static final long CKR_CRYPTOKI_ALREADY_INITIALIZED = 0x191L;
    private static final FunctionDescriptor INITIALIZE_OR_FINALIZE = FunctionDescriptor.of(
            ValueLayout.JAVA_LONG, ValueLayout.ADDRESS);
    private static final FunctionDescriptor GET_SLOT_LIST = FunctionDescriptor.of(ValueLayout.JAVA_LONG,
            ValueLayout.JAVA_BYTE, ValueLayout.ADDRESS, ValueLayout.ADDRESS);

    private PKCS11TokenPresenceProbe() {
    }

    static Optional<Boolean> tokenPresent(Path libraryPath) {
        try (var arena = Arena.ofConfined()) {
            var symbols = SymbolLookup.libraryLookup(libraryPath, arena);
            var initialize = downcall(symbols, "C_Initialize", INITIALIZE_OR_FINALIZE);
            var getSlotList = downcall(symbols, "C_GetSlotList", GET_SLOT_LIST);
            var finalize = downcall(symbols, "C_Finalize", INITIALIZE_OR_FINALIZE);

            var initializeResult = invoke(initialize, MemorySegment.NULL);
            if (initializeResult != CKR_OK && initializeResult != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
                return Optional.empty();
            }

            try {
                var slotCount = arena.allocate(ValueLayout.JAVA_LONG);
                if (invoke(getSlotList, (byte) 1, MemorySegment.NULL, slotCount) != CKR_OK) {
                    return Optional.empty();
                }
                return Optional.of(slotCount.get(ValueLayout.JAVA_LONG, 0) > 0);
            } finally {
                if (initializeResult == CKR_OK) {
                    invoke(finalize, MemorySegment.NULL);
                }
            }
        } catch (Throwable ignored) {
            return Optional.empty();
        }
    }

    private static MethodHandle downcall(SymbolLookup symbols, String name, FunctionDescriptor descriptor) {
        var address = symbols.find(name).orElseThrow();
        return Linker.nativeLinker().downcallHandle(address, descriptor);
    }

    private static long invoke(MethodHandle handle, Object... arguments) throws Throwable {
        return (long) handle.invokeWithArguments(arguments);
    }
}
