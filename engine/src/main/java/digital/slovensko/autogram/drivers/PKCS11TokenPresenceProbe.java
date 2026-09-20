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
import java.util.OptionalInt;

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
            var session = open(libraryPath, arena);
            if (session == null) {
                return Optional.empty();
            }
            try {
                return Optional.of(slotIds(session, arena, true).length > 0);
            } finally {
                session.close();
            }
        } catch (Throwable ignored) {
            return Optional.empty();
        }
    }

    /**
     * SunPKCS11 {@code slotListIndex} into {@code C_GetSlotList(false)}.
     * I.CA SecureStore often exposes an empty reader at 0 and the card at 1, but a
     * single reader puts the card at 0: hardcoded 1 then yields CKR_TOKEN_NOT_RECOGNIZED.
     */
    static OptionalInt firstTokenSlotIndex(Path libraryPath) {
        try (var arena = Arena.ofConfined()) {
            var session = open(libraryPath, arena);
            if (session == null) {
                return OptionalInt.empty();
            }
            try {
                var allSlots = slotIds(session, arena, false);
                var tokenSlots = slotIds(session, arena, true);
                var index = slotListIndexOf(allSlots, tokenSlots);
                return index >= 0 ? OptionalInt.of(index) : OptionalInt.empty();
            } finally {
                session.close();
            }
        } catch (Throwable ignored) {
            return OptionalInt.empty();
        }
    }

    static int slotListIndexOf(long[] allSlots, long[] tokenSlots) {
        if (allSlots == null || tokenSlots == null || tokenSlots.length == 0) {
            return -1;
        }
        var slotId = tokenSlots[0];
        for (var i = 0; i < allSlots.length; i++) {
            if (allSlots[i] == slotId) {
                return i;
            }
        }
        return -1;
    }


    private static Session open(Path libraryPath, Arena arena) throws Throwable {
        var symbols = SymbolLookup.libraryLookup(libraryPath, arena);
        var initialize = downcall(symbols, "C_Initialize", INITIALIZE_OR_FINALIZE);
        var getSlotList = downcall(symbols, "C_GetSlotList", GET_SLOT_LIST);
        var finalize = downcall(symbols, "C_Finalize", INITIALIZE_OR_FINALIZE);
        var initializeResult = invoke(initialize, MemorySegment.NULL);
        if (initializeResult != CKR_OK && initializeResult != CKR_CRYPTOKI_ALREADY_INITIALIZED) {
            return null;
        }
        return new Session(getSlotList, finalize, initializeResult == CKR_OK);
    }

    private static long[] slotIds(Session session, Arena arena, boolean tokenPresent) throws Throwable {
        var slotCount = arena.allocate(ValueLayout.JAVA_LONG);
        var present = tokenPresent ? (byte) 1 : (byte) 0;
        if (invoke(session.getSlotList, present, MemorySegment.NULL, slotCount) != CKR_OK) {
            return new long[0];
        }
        var count = slotCount.get(ValueLayout.JAVA_LONG, 0);
        if (count <= 0) {
            return new long[0];
        }
        var buffer = arena.allocate(ValueLayout.JAVA_LONG, count);
        if (invoke(session.getSlotList, present, buffer, slotCount) != CKR_OK) {
            return new long[0];
        }
        count = slotCount.get(ValueLayout.JAVA_LONG, 0);
        var ids = new long[(int) count];
        for (var i = 0; i < ids.length; i++) {
            ids[i] = buffer.getAtIndex(ValueLayout.JAVA_LONG, i);
        }
        return ids;
    }

    private static MethodHandle downcall(SymbolLookup symbols, String name, FunctionDescriptor descriptor) {
        var address = symbols.find(name).orElseThrow();
        return Linker.nativeLinker().downcallHandle(address, descriptor);
    }

    private static long invoke(MethodHandle handle, Object... arguments) throws Throwable {
        return (long) handle.invokeWithArguments(arguments);
    }

    private record Session(MethodHandle getSlotList, MethodHandle finalizeFn, boolean ownsInitialize) {
        void close() {
            if (ownsInitialize) {
                try {
                    invoke(finalizeFn, MemorySegment.NULL);
                } catch (Throwable ignored) {
                }
            }
        }
    }
}
