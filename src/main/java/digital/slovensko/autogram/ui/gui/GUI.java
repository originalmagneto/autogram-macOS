package digital.slovensko.autogram.ui.gui;

import java.io.File;
import java.io.IOException;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;
import java.util.WeakHashMap;
import java.util.ArrayList;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;
import java.util.function.Consumer;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.ScheduledExecutorService;

import digital.slovensko.autogram.core.*;
import digital.slovensko.autogram.core.errors.*;
import digital.slovensko.autogram.core.visualization.Visualization;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.BatchUiResult;
import digital.slovensko.autogram.ui.UI;
import digital.slovensko.autogram.util.PDFUtils;
import digital.slovensko.autogram.util.macos.MacOSNotification;
import eu.europa.esig.dss.model.DSSDocument;
import eu.europa.esig.dss.token.DSSPrivateKeyEntry;
import javafx.application.HostServices;
import javafx.application.Platform;
import javafx.geometry.Rectangle2D;
import javafx.scene.Parent;
import javafx.scene.Scene;
import javafx.stage.Modality;
import javafx.stage.Screen;
import javafx.stage.Stage;
import javafx.stage.Window;

public class GUI implements UI {
    private final Map<SigningJob, SigningDialogController> jobControllers = new WeakHashMap<>();
    private SigningKey activeKey;
    private char[] batchPin;
    private boolean driverWasAlreadySet = false;
    private final HostServices hostServices;
    private final UserSettings userSettings;
    private BatchQueueController batchQueueController;
    private MainMenuController mainMenuController;

    private int nWindows = 0;
    public final ScheduledExecutorService scheduledExecutorService;
    public final ExecutorService cachedExecutorService;

    public GUI(HostServices hostServices, UserSettings userSettings, ScheduledExecutorService scheduledExecutorService,
            ExecutorService cachedExecutorService) {
        this.hostServices = hostServices;
        this.userSettings = userSettings;
        this.scheduledExecutorService = scheduledExecutorService;
        this.cachedExecutorService = cachedExecutorService;
    }

    public void setMainMenuController(MainMenuController controller) {
        this.mainMenuController = controller;
    }

    @Override
    public void startSigning(SigningJob job, Autogram autogram) {
        autogram.startVisualization(job);
    }

    @Override
    public void startBatch(Batch batch, Autogram autogram, BatchStartCallback callback) {
        if (mainMenuController != null) {
            batchQueueController = new BatchQueueController();
            var root = GUIUtils.loadFXML(batchQueueController, "batch-queue.fxml");
            batchQueueController.initialize(mainMenuController, autogram, batch, callback);
            mainMenuController.showRightDrawer(root);
        } else {
            // Fallback: no main menu yet — cancel since we can't display the batch UI
            callback.cancel();
        }
    }

    @Override
    public void cancelBatch(Batch batch) {
        if (batchQueueController != null) {
            batchQueueController.onBatchEnded();
        }
        batch.end();
        refreshKeyOnAllJobs();
        enableSigningOnAllJobs();
    }

    public void updateBatch() {
        if (batchQueueController != null) {
            batchQueueController.update();
        }
    }

    public void updateBatchItemStatus(File file, String status, String styleClass) {
        if (batchQueueController != null) {
            batchQueueController.updateStatus(file, status, styleClass);
        }
    }

    @Override
    public void pickTokenDriverAndThen(List<TokenDriver> drivers, Consumer<TokenDriver> callback, Runnable onCancel) {
        disableKeyPicking();

        if (drivers.isEmpty()) {
            showError(new NoDriversDetectedException());
            refreshKeyOnAllJobs();
            enableSigningOnAllJobs();
        } else if (drivers.size() == 1) {
            // short-circuit if only one driver present
            callback.accept(drivers.get(0));
        } else {
            if (!driverWasAlreadySet && userSettings.getDefaultDriver() != null) {
                try {
                    driverWasAlreadySet = true;
                    var defaultDriver = drivers.stream()
                            .filter(d -> d.getName().equals(userSettings.getDefaultDriver()))
                            .findFirst().get();

                    if (defaultDriver != null) {
                        callback.accept(defaultDriver);
                        return;
                    }
                } catch (NoSuchElementException e) {
                }
            }

            PickDriverDialogController controller = new PickDriverDialogController(drivers, callback);
            var root = GUIUtils.loadFXML(controller, "pick-driver-dialog.fxml");

            if (mainMenuController != null) {
                controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
                controller.setOnCancel(onCancel);
                mainMenuController.showOverlayDialog(root, OverlaySpec.compact()
                        .withAutoFocus(".radio-button")
                        .withCancelAction("#cancelButton")
                        .withCloseOnEscape(true));
            } else {
                var stage = new Stage();
                stage.setTitle("Výber úložiska certifikátu");
                stage.setScene(new Scene(root));

                // Handle cancellation via controller (Cancel button)
                controller.setOnCancel(onCancel);

                // Handle cancellation via X button
                stage.setOnCloseRequest(e -> {
                    refreshKeyOnAllJobs();
                    enableSigningOnAllJobs();
                    if (onCancel != null)
                        onCancel.run();
                });
                stage.sizeToScene();
                stage.setResizable(false);
                stage.initModality(Modality.APPLICATION_MODAL);
                stage.show();
            }
        }
    }

    @Override
    public void pickKeyAndThen(List<DSSPrivateKeyEntry> keys, TokenDriver driver,
            Consumer<DSSPrivateKeyEntry> callback) {
        if (keys.isEmpty()) {
            showError(new NoKeysDetectedException(driver.getNoKeysHelperText()));
            refreshKeyOnAllJobs();
            enableSigningOnAllJobs();

            return;
        }

        var keysStream = keys.stream();
        // TODO: NFC eID returns false for qualified certificate #367
        // var keysStream = keys.stream().filter(k ->
        // k.getCertificate().checkKeyUsage(KeyUsageBit.DIGITAL_SIGNATURE));
        if (!userSettings.isExpiredCertsEnabled()) {
            var now = new Date();
            keysStream = keysStream.filter(k -> k.getCertificate().isValidOn(now));
        }

        keys = keysStream.toList();
        if (keys.isEmpty()) {
            showError(new NoValidKeysDetectedException());
            refreshKeyOnAllJobs();
            enableSigningOnAllJobs();

            return;
        }

        var controller = new PickKeyDialogController(keys, callback, userSettings.isExpiredCertsEnabled());
        var root = GUIUtils.loadFXML(controller, "pick-key-dialog.fxml");

        if (mainMenuController != null) {
            controller.setOnCancel(() -> {
                refreshKeyOnAllJobs();
                enableSigningOnAllJobs();
            });
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.compact()
                    .withAutoFocus(".radio-button")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("Výber certifikátu");
            stage.setScene(new Scene(root));
            stage.setOnCloseRequest(e -> {
                refreshKeyOnAllJobs();
                enableSigningOnAllJobs();
            });
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);
            stage.show();
        }
    }

    public void refreshKeyOnAllJobs() {
        jobControllers.values().forEach(SigningDialogController::refreshSigningKey);
    }

    public void enableSigningOnAllJobs() {
        jobControllers.values().forEach(SigningDialogController::enableSigning);
    }

    @Override
    public void showError(AutogramException e) {
        if (mainMenuController != null) {
            var controller = new ErrorController(e);
            var root = GUIUtils.loadFXML(controller, "error-dialog.fxml");
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#mainButton")
                    .withCancelAction("#mainButton")
                    .withCloseOnEscape(true));
        } else {
            GUIUtils.showError(e, "Pokračovať", false);
        }
    }

    public void showPkcsEidWindowsDllError(AutogramException e) {
        var controller = new PkcsEidWindowsDllErrorController(hostServices);
        var root = GUIUtils.loadFXML(controller, "pkcs-eid-windows-dll-error-dialog.fxml");

        if (mainMenuController != null) {
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#mainButton")
                    .withCancelAction("#mainButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle(e.getSubheading());
            stage.setScene(new Scene(root));

            stage.sizeToScene();
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);

            GUIUtils.suppressDefaultFocus(stage, controller);

            stage.show();
        }
    }

    public char[] getKeystorePassword() {
        if (mainMenuController != null) {
            var latch = new java.util.concurrent.CountDownLatch(1);
            var controller = new PasswordController("Aký je kód k úložisku klúčov?", "Zadajte kód k úložisku klúčov.",
                    false, true);

            Platform.runLater(() -> {
                var root = GUIUtils.loadFXML(controller, "password-dialog.fxml");
                controller.setOnClose(() -> {
                    mainMenuController.hideOverlayDialog();
                    latch.countDown();
                });
                mainMenuController.showOverlayDialog(root, OverlaySpec.compact()
                        .withAutoFocus("#passwordField")
                        .withCancelAction("#cancelButton")
                        .withCloseOnEscape(true));
            });

            try {
                latch.await();
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
            return controller.getPassword();
        }

        var futurePassword = new FutureTask<>(() -> {
            var controller = new PasswordController("Aký je kód k úložisku klúčov?", "Zadajte kód k úložisku klúčov.",
                    false, true);
            var root = GUIUtils.loadFXML(controller, "password-dialog.fxml");

            var stage = new Stage();
            stage.setTitle("Načítanie klúčov z úložiska");
            stage.setScene(new Scene(root));
            stage.setOnCloseRequest(e -> {
                refreshKeyOnAllJobs();
                enableSigningOnAllJobs();
            });
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);
            stage.showAndWait();

            return controller.getPassword();
        });

        Platform.runLater(futurePassword);

        try {
            return futurePassword.get();
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException(e);
        }
    }

    public char[] getContextSpecificPassword() {
        if (batchPin != null) {
            return batchPin;
        }

        if (mainMenuController != null) {
            var latch = new java.util.concurrent.CountDownLatch(1);
            var controller = new PasswordController("Aký je podpisový PIN alebo heslo?",
                    "Zadajte podpisový PIN alebo heslo ku klúču.", true, false);

            Platform.runLater(() -> {
                var root = GUIUtils.loadFXML(controller, "password-dialog.fxml");
                controller.setOnClose(() -> {
                    mainMenuController.hideOverlayDialog();
                    latch.countDown();
                });
                mainMenuController.showOverlayDialog(root, OverlaySpec.compact()
                        .withAutoFocus("#passwordField")
                        .withCancelAction("#cancelButton")
                        .withCloseOnEscape(true));
            });

            try {
                latch.await();
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
            return controller.getPassword();
        }

        var futurePassword = new FutureTask<>(() -> {
            var controller = new PasswordController("Aký je podpisový PIN alebo heslo?",
                    "Zadajte podpisový PIN alebo heslo ku klúču.", true, false);
            var root = GUIUtils.loadFXML(controller, "password-dialog.fxml");

            var stage = new Stage();
            stage.setTitle("Zadanie podpisového PINu alebo hesla");
            stage.setScene(new Scene(root));
            stage.setOnCloseRequest(e -> {
                refreshKeyOnAllJobs();
                enableSigningOnAllJobs();
            });
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);
            stage.showAndWait();

            return controller.getPassword();
        });

        Platform.runLater(futurePassword);

        try {
            return futurePassword.get();
        } catch (InterruptedException | ExecutionException e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public void onUpdateAvailable() {
        var controller = new UpdateController(hostServices);
        var root = GUIUtils.loadFXML(controller, "update-dialog.fxml");

        if (mainMenuController != null) {
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#mainButton")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("Dostupná aktualizácia");
            stage.setScene(new Scene(root));
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);
            GUIUtils.suppressDefaultFocus(stage, controller);
            stage.show();
        }
    }

    @Override
    public void onAboutInfo() {
        var controller = new AboutDialogController(hostServices);
        var root = GUIUtils.loadFXML(controller, "about-dialog.fxml");

        if (mainMenuController != null) {
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.wide()
                    .withAutoFocus("#closeButton")
                    .withCancelAction("#closeButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("O projekte Autogram");
            stage.setScene(new Scene(root));
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);
            GUIUtils.suppressDefaultFocus(stage, controller);
            stage.show();
        }
    }

    @Override
    public void onPDFAComplianceCheckFailed(SigningJob job) {
        if (mainMenuController != null) {
            mainMenuController.updateFormatMetadata("PDF (nie PDF/A compliant)");
            var signingController = jobControllers.get(job);
            if (signingController != null) {
                signingController.showPdfaInlineWarning();
                return;
            }
            var controller = new PDFAComplianceDialogController(job, this);
            var root = GUIUtils.loadFXML(controller, "pdfa-compliance-dialog.fxml");
            controller.setOnClose(() -> mainMenuController.hideOverlayDialog());
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#continueButton")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var controller = new PDFAComplianceDialogController(job, this);
            var root = GUIUtils.loadFXML(controller, "pdfa-compliance-dialog.fxml");
            var stage = new Stage();
            GUIUtils.setAppIcon(stage);
            stage.setTitle("Dokument nie je vo formáte PDF/A");
            stage.setScene(new Scene(root));
            stage.setResizable(false);
            stage.initModality(Modality.WINDOW_MODAL);
            stage.initOwner(getJobWindow(job));
            GUIUtils.suppressDefaultFocus(stage, controller);
            stage.show();
        }
    }

    @Override
    public void onSignatureValidationCompleted(ValidationReports reports) {
        var controller = jobControllers.get(reports.getSigningJob());
        controller.onSignatureValidationCompleted(reports.getReports());
    }

    @Override
    public void onSignatureCheckCompleted(ValidationReports reports) {
        var controller = jobControllers.get(reports.getSigningJob());
        controller.onSignatureCheckCompleted(reports.haveSignatures() ? reports.getReports() : null);

        // Extract and show existing signatures in the sidebar
        if (mainMenuController != null && reports.haveSignatures()) {
            var reportsData = reports.getReports();
            var simpleReport = reportsData.getSimpleReport();
            var signatures = simpleReport.getSignatureIdList();
            List<String> signerNames = new ArrayList<>();
            for (String sigId : signatures) {
                signerNames.add(simpleReport.getSignedBy(sigId));
            }
            mainMenuController.updateExistingSignatures(signerNames);
        } else if (mainMenuController != null) {
            mainMenuController.updateExistingSignatures(null);
        }
    }

    public void showVisualization(Visualization visualization, Autogram autogram) {
        var doc = visualization.getJob().getDocument();
        var title = "Dokument";
        if (doc.getName() != null)
            title += " " + doc.getName();

        var controller = new SigningDialogController(visualization, autogram, this, title,
                userSettings.isSignaturesValidity());
        controller.setMainMenuController(mainMenuController);
        jobControllers.put(visualization.getJob(), controller);

        Parent root;
        try {
            root = GUIUtils.loadFXML(controller, "signing-dialog.fxml");
        } catch (AutogramException e) {
            showError(e);
            return;
        } catch (Exception e) {
            showError(new UnrecognizedException(e));
            return;
        }

        // Embed signing visualization in the main window's content area
        if (mainMenuController != null) {
            // Update metadata
            String filename = doc.getName() != null ? doc.getName() : "Neznámy";
            String size = formatFileSize(doc);
            String pages = formatPageCount(doc);
            String format = doc.getMimeType().getMimeTypeString();
            String cert = activeKey != null ? activeKey.toString() : "Nevybraný";

            mainMenuController.updateMetadata(filename, size, pages, format, cert);

            // Extract existing signatures if it's already a job we might know about
            // Or it will be handled by onSignatureCheckCompleted soon

            mainMenuController.showSigningContent(root);
        } else {
            // Fallback: open in a separate stage
            var stage = new Stage();
            GUIUtils.setAppIcon(stage);
            stage.setTitle(title);
            stage.setScene(new Scene(root));
            stage.setOnCloseRequest(e -> cancelJob(visualization.getJob()));
            stage.sizeToScene();
            GUIUtils.suppressDefaultFocus(stage, controller);
            GUIUtils.showOnTop(stage);
            GUIUtils.hackToForceRelayout(stage);
            setUserFriendlyPositionAndLimits(stage);
        }

        onWorkThreadDo(() -> autogram.checkAndValidateSignatures(visualization.getJob()));
    }

    private String formatFileSize(DSSDocument doc) {
        try {
            long bytes = doc.openStream().available();
            if (bytes < 1024)
                return bytes + " B";
            int exp = (int) (Math.log(bytes) / Math.log(1024));
            char pre = "KMGTPE".charAt(exp - 1);
            return String.format("%.1f %sB", bytes / Math.pow(1024, exp), pre);
        } catch (IOException e) {
            return "Neznáma";
        }
    }

    private String formatPageCount(DSSDocument doc) {
        int pages = PDFUtils.getPageCount(doc);
        return pages > 0 ? String.valueOf(pages) : "N/A";
    }

    @Override
    public void showIgnorableExceptionDialog(IgnorableException e) {
        var controller = new IgnorableExceptionDialogController(e);
        var root = GUIUtils.loadFXML(controller, "ignorable-exception-dialog.fxml");

        var stage = new Stage();
        stage.setTitle("Chyba pri zobrazovaní dokumentu");
        stage.setScene(new Scene(root));
        stage.setResizable(false);
        stage.initModality(Modality.WINDOW_MODAL);
        stage.initOwner(getJobWindow(e.getJob()));
        GUIUtils.suppressDefaultFocus(stage, controller);

        GUIUtils.showOnTop(stage);
    }

    private void disableKeyPicking() {
        jobControllers.values().forEach(SigningDialogController::disableKeyPicking);
    }

    @Override
    public void onPickSigningKeyFailed(AutogramException e) {
        if (e instanceof PkcsEidWindowsDllException)
            showPkcsEidWindowsDllError(e);
        else if (!showSigningInlineErrorOnAnyOpenJob(e))
            showError(e);

        resetSigningKey();
        enableSigningOnAllJobs();
    }

    @Override
    public void onSigningSuccess(SigningJob job) {
        var controller = jobControllers.get(job);
        if (controller != null) {
            // Don't close the window if we're in single-window mode
            if (mainMenuController == null) {
                controller.close();
            }
        }
        refreshKeyOnAllJobs();
        enableSigningOnAllJobs();
        updateBatch();
    }

    @Override
    public void onSigningFailed(AutogramException e, SigningJob job) {
        var controller = jobControllers.get(job);
        if (controller == null) {
            onSigningFailed(e);
            return;
        }

        if (mainMenuController != null) {
            controller.showSigningErrorInline(e);
            refreshKeyOnAllJobs();
            enableSigningOnAllJobs();
            return;
        }

        controller.close();
        jobControllers.remove(job);
        onSigningFailed(e);
    }

    @Override
    public void onSigningFailed(AutogramException e) {
        if (!showSigningInlineErrorOnAnyOpenJob(e)) {
            showError(e);
        }
        if (e instanceof TokenRemovedException) {
            resetSigningKey();
        } else {
            refreshKeyOnAllJobs();
        }
        enableSigningOnAllJobs();
    }

    private boolean showSigningInlineErrorOnAnyOpenJob(AutogramException e) {
        if (mainMenuController == null || jobControllers.isEmpty()) {
            return false;
        }

        for (var controller : jobControllers.values()) {
            if (controller != null) {
                controller.showSigningErrorInline(e);
                return true;
            }
        }
        return false;
    }

    @Override
    public void onDocumentSaved(File targetFile) {
        var controller = new SigningSuccessDialogController(targetFile, hostServices);
        var root = GUIUtils.loadFXML(controller, "signing-success-dialog.fxml");

        // Show success inline in main window
        if (mainMenuController != null) {
            controller.setOnClose(() -> mainMenuController.showDropZone());
            controller.setOnSignAnother(() -> mainMenuController.showDropZone());
            mainMenuController.showSuccessContent(root);
        } else {
            var stage = new Stage();
            GUIUtils.setAppIcon(stage);
            stage.setTitle("Dokument bol úspešne podpísaný");
            stage.setScene(new Scene(root));
            stage.setResizable(false);
            GUIUtils.suppressDefaultFocus(stage, controller);
            stage.show();
        }
        MacOSNotification.notify("Autogram", "Dokument " + targetFile.getName() + " bol podpísaný");
    }

    @Override
    public void onDocumentBatchSaved(BatchUiResult result) {
        SuppressedFocusController controller;
        Parent root;
        String title;
        if (result.hasErrors()) {
            var failureController = new BatchSigningFailureDialogController(result, hostServices);
            controller = failureController;
            root = GUIUtils.loadFXML(controller, "batch-signing-failure-dialog.fxml");
            title = "Hromadné podpisovanie ukončené s chybami";
            if (mainMenuController != null) {
                failureController.setOnClose(() -> mainMenuController.hideOverlayDialog());
            }
        } else {
            var successController = new BatchSigningSuccessDialogController(result, hostServices);
            controller = successController;
            root = GUIUtils.loadFXML(controller, "batch-signing-success-dialog.fxml");
            title = "Hromadné podpisovanie úspešne ukončené";
            if (mainMenuController != null) {
                successController.setOnClose(() -> {
                    mainMenuController.hideOverlayDialog();
                    mainMenuController.showDropZone();
                });
            }
        }

        if (mainMenuController != null) {
            mainMenuController.showOverlayDialog(root, OverlaySpec.wide()
                    .withAutoFocus("#mainButton")
                    .withCancelAction("#mainButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle(title);
            stage.setScene(new Scene(root));
            stage.setResizable(false);
            stage.sizeToScene();
            GUIUtils.suppressDefaultFocus(stage, controller);
            stage.show();
        }

        enableSigningOnAllJobs();
    }

    @Override
    public void onWorkThreadDo(Runnable callback) {
        if (Platform.isFxApplicationThread()) {
            new Thread(callback).start();
        } else {
            callback.run();
        }
    }

    @Override
    public void onUIThreadDo(Runnable callback) {
        if (Platform.isFxApplicationThread()) {
            callback.run();
        } else {
            Platform.runLater(callback);
        }
    }

    public SigningKey getActiveSigningKey() {
        return activeKey;
    }

    public void setActiveSigningKeyAndThen(SigningKey newKey, Consumer<SigningKey> callback) {
        if (!isActiveSigningKeyChangeAllowed())
            throw new RuntimeException("Signing key change is not allowed");

        if (activeKey != null)
            activeKey.close();

        activeKey = newKey;
        driverWasAlreadySet = true;
        refreshKeyOnAllJobs();

        if (callback != null)
            callback.accept(newKey);
        else
            enableSigningOnAllJobs();
    }

    public boolean isActiveSigningKeyChangeAllowed() {
        return true;
    }

    public void disableSigning() {
        jobControllers.values().forEach(SigningDialogController::disableSigning);
    }

    @Override
    public void resetSigningKey() {
        onUIThreadDo(() -> {
            setActiveSigningKeyAndThen(null, null);
            refreshKeyOnAllJobs();
        });
    }

    public void cancelJob(SigningJob job) {
        job.onDocumentSignFailed(new SigningCanceledByUserException());
        jobControllers.get(job).close();
    }

    public void focusJob(SigningJob job) {
        getJobWindow(job).requestFocus();
    }

    private Window getJobWindow(SigningJob job) {
        return jobControllers.get(job).mainBox.getScene().getWindow();
    }

    private void setUserFriendlyPositionAndLimits(Stage stage) {
        var maxWindows = 10;
        var maxOffset = 25;
        Rectangle2D bounds = Screen.getPrimary().getVisualBounds();
        var sceneWidth = stage.getScene().getWidth();
        var availabeWidth = (bounds.getWidth() - sceneWidth);
        var singleOffsetXPx = Math.round(Math.min(maxOffset, (availabeWidth / 2) / maxWindows)); // spread windows into
        // half of availabe
        // screen width
        var offsetX = singleOffsetXPx * (nWindows - maxWindows / 2);
        double idealX = bounds.getMinX() + availabeWidth / 2 + offsetX;
        double x = Math.max(bounds.getMinX(), Math.min(bounds.getMaxX() - sceneWidth, idealX));
        var sceneHeight = stage.getScene().getHeight();
        double y = Math.max(bounds.getMinY(),
                Math.min(bounds.getMaxY() - sceneHeight, bounds.getMinY() + (bounds.getHeight() - sceneHeight) / 2));
        stage.setX(x);
        stage.setY(y);
        stage.setMaxHeight(bounds.getHeight());
        stage.setMaxWidth(bounds.getWidth());
        nWindows = (nWindows + 1) % maxWindows;
    }

    @Override
    public void consentCertificateReadingAndThen(Consumer<Runnable> callback, Runnable onCancel) {
        var controller = new ConsentCertificateReadingDialogController(callback, onCancel);
        var root = GUIUtils.loadFXML(controller, "consent-certificate-reading-dialog.fxml");

        if (mainMenuController != null) {
            controller.setOnClose(mainMenuController::hideOverlayDialog);
            mainMenuController.showOverlayDialog(root, OverlaySpec.defaults()
                    .withAutoFocus("#continueButton")
                    .withCancelAction("#cancelButton")
                    .withCloseOnEscape(true));
        } else {
            var stage = new Stage();
            stage.setTitle("Súhlas - Zoznam podpisových certifikátov");
            stage.setScene(new Scene(root));

            stage.sizeToScene();
            stage.setResizable(false);
            stage.initModality(Modality.APPLICATION_MODAL);

            stage.setOnCloseRequest(e -> {
                if (onCancel != null)
                    onCancel.run();
            });

            GUIUtils.suppressDefaultFocus(stage, controller);

            stage.show();
        }
    }

    public void setBatchPin(char[] pin) {
        this.batchPin = pin;
    }

    public void clearBatchPin() {
        this.batchPin = null;
    }
}
