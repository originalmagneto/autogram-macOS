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
import java.util.function.Supplier;

public final class MachineTrustService {
    private static final Duration LOAD_TIMEOUT = Duration.ofSeconds(60);
    private static final Duration POLL_INTERVAL = Duration.ofMillis(50);

    private final Supplier<ExecutorService> executorFactory;
    private final Consumer<ExecutorService> initializer;
    private final BooleanSupplier trustedListsLoaded;
    private final Duration loadTimeout;
    private final Duration pollInterval;

    public MachineTrustService() {
        this(() -> Executors.newFixedThreadPool(2),
                executor -> SignatureValidator.getInstance().initialize(executor, new MachineSettings().getTrustedList()),
                () -> SignatureValidator.getInstance().areTLsLoaded(),
                LOAD_TIMEOUT,
                POLL_INTERVAL);
    }

    MachineTrustService(Supplier<ExecutorService> executorFactory, Consumer<ExecutorService> initializer,
            BooleanSupplier trustedListsLoaded, Duration loadTimeout, Duration pollInterval) {
        this.executorFactory = executorFactory;
        this.initializer = initializer;
        this.trustedListsLoaded = trustedListsLoaded;
        this.loadTimeout = loadTimeout;
        this.pollInterval = pollInterval;
    }

    public void initialize() {
        var executor = executorFactory.get();
        try {
            Future<?> initialization = executor.submit(() -> initializer.accept(executor));
            waitForTrustedLists(initialization);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw unavailable(exception);
        } catch (ExecutionException | RuntimeException exception) {
            throw unavailable(exception);
        } finally {
            executor.shutdownNow();
        }
    }

    private void waitForTrustedLists(Future<?> initialization) throws InterruptedException, ExecutionException {
        var deadline = System.nanoTime() + loadTimeout.toNanos();
        while (true) {
            if (initialization.isDone()) {
                initialization.get();
                if (areTrustedListsLoaded()) {
                    return;
                }
            }
            var remainingNanos = deadline - System.nanoTime();
            if (remainingNanos <= 0) {
                throw unavailable(null);
            }
            var sleepNanos = Math.min(remainingNanos, pollInterval.toNanos());
            if (sleepNanos > 0) {
                TimeUnit.NANOSECONDS.sleep(sleepNanos);
            }
        }
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
}
