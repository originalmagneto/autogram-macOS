package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.SignatureValidator;

import java.time.Duration;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

public final class MachineTrustService {
    private static final Duration LOAD_TIMEOUT = Duration.ofSeconds(60);
    private static final Duration POLL_INTERVAL = Duration.ofMillis(50);

    private final Supplier<ExecutorService> executorFactory;
    private final Consumer<ExecutorService> initializer;
    private final BooleanSupplier trustedListsLoaded;
    private final Duration loadTimeout;
    private final Duration pollInterval;
    private final LongSupplier nanoTime;
    private final Sleeper sleeper;

    public MachineTrustService() {
        this(() -> Executors.newFixedThreadPool(2),
                executor -> SignatureValidator.getInstance().initialize(executor, new MachineSettings().getTrustedList()),
                () -> SignatureValidator.getInstance().areTLsLoaded(),
                LOAD_TIMEOUT,
                POLL_INTERVAL,
                System::nanoTime,
                TimeUnit.NANOSECONDS::sleep);
    }

    MachineTrustService(Supplier<ExecutorService> executorFactory, Consumer<ExecutorService> initializer,
            BooleanSupplier trustedListsLoaded, Duration loadTimeout, Duration pollInterval) {
        this(executorFactory, initializer, trustedListsLoaded, loadTimeout, pollInterval, System::nanoTime,
                TimeUnit.NANOSECONDS::sleep);
    }

    MachineTrustService(Supplier<ExecutorService> executorFactory, Consumer<ExecutorService> initializer,
            BooleanSupplier trustedListsLoaded, Duration loadTimeout, Duration pollInterval, LongSupplier nanoTime,
            Sleeper sleeper) {
        this.executorFactory = executorFactory;
        this.initializer = initializer;
        this.trustedListsLoaded = trustedListsLoaded;
        this.loadTimeout = loadTimeout;
        this.pollInterval = pollInterval;
        this.nanoTime = nanoTime;
        this.sleeper = sleeper;
    }

    public void initialize() {
        var executor = executorFactory.get();
        var deadline = nanoTime.getAsLong() + loadTimeout.toNanos();
        try {
            Future<?> initialization = executor.submit(() -> initializer.accept(executor));
            waitForTrustedLists(initialization, deadline);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw unavailable(exception);
        } catch (ExecutionException | RuntimeException exception) {
            throw unavailable(exception);
        } finally {
            closeExecutor(executor, deadline);
        }
    }

    private void waitForTrustedLists(Future<?> initialization, long deadline) throws InterruptedException, ExecutionException {
        while (true) {
            if (initialization.isDone()) {
                initialization.get();
                if (areTrustedListsLoaded()) {
                    return;
                }
            }
            var remainingNanos = remainingNanos(deadline);
            if (remainingNanos <= 0) {
                throw unavailable(null);
            }
            var sleepNanos = Math.min(remainingNanos, pollInterval.toNanos());
            if (sleepNanos > 0) {
                sleeper.sleep(sleepNanos);
            }
        }
    }

    private void closeExecutor(ExecutorService executor, long deadline) {
        executor.shutdownNow();
        try {
            if (!executor.awaitTermination(remainingNanos(deadline), TimeUnit.NANOSECONDS)) {
                throw unavailable(null);
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw unavailable(exception);
        }
    }

    private long remainingNanos(long deadline) {
        return Math.max(0, deadline - nanoTime.getAsLong());
    }

    private static MachineProtocolException unavailable(Throwable cause) {
        return cause == null
                ? new MachineProtocolException("TRUSTED_LIST_UNAVAILABLE")
                : new MachineProtocolException("TRUSTED_LIST_UNAVAILABLE", cause);
    }

    private boolean areTrustedListsLoaded() {
        try {
            return trustedListsLoaded.getAsBoolean();
        } catch (NullPointerException exception) {
            return false;
        }
    }

    @FunctionalInterface
    interface Sleeper {
        void sleep(long nanos) throws InterruptedException;
    }
}
