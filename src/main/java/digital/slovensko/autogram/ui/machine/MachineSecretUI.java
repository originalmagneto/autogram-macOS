package digital.slovensko.autogram.ui.machine;

import digital.slovensko.autogram.core.Autogram;
import digital.slovensko.autogram.core.Batch;
import digital.slovensko.autogram.core.BatchStartCallback;
import digital.slovensko.autogram.core.SigningJob;
import digital.slovensko.autogram.core.ValidationReports;
import digital.slovensko.autogram.core.errors.AutogramException;
import digital.slovensko.autogram.core.visualization.Visualization;
import digital.slovensko.autogram.drivers.TokenDriver;
import digital.slovensko.autogram.ui.UI;
import digital.slovensko.autogram.ui.BatchUiResult;
import digital.slovensko.autogram.ui.gui.IgnorableException;
import eu.europa.esig.dss.token.DSSPrivateKeyEntry;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Consumer;

public final class MachineSecretUI implements UI, AutoCloseable {
    private final char[] secret;
    private final List<char[]> issuedSecrets = new ArrayList<>();

    public MachineSecretUI(char[] secret) {
        this.secret = secret.clone();
    }

    @Override
    public char[] getKeystorePassword() {
        return issueSecret();
    }

    @Override
    public char[] getContextSpecificPassword() {
        return issueSecret();
    }

    @Override
    public void close() {
        Arrays.fill(secret, '\0');
        issuedSecrets.forEach(value -> Arrays.fill(value, '\0'));
        issuedSecrets.clear();
    }

    private char[] issueSecret() {
        var issuedSecret = secret.clone();
        issuedSecrets.add(issuedSecret);
        return issuedSecret;
    }

    @Override
    public void startSigning(SigningJob job, Autogram autogram) {
        throw unavailable();
    }

    @Override
    public void startBatch(Batch batch, Autogram autogram, BatchStartCallback callback) {
        throw unavailable();
    }

    @Override
    public void cancelBatch(Batch batch) {
        throw unavailable();
    }

    @Override
    public void showVisualization(Visualization visualization, Autogram autogram) {
        throw unavailable();
    }

    @Override
    public void pickTokenDriverAndThen(List<TokenDriver> drivers, Consumer<TokenDriver> callback, Runnable onCancel) {
        throw unavailable();
    }

    @Override
    public void pickKeyAndThen(List<DSSPrivateKeyEntry> keys, TokenDriver driver, Consumer<DSSPrivateKeyEntry> callback) {
        throw unavailable();
    }

    @Override
    public void onPickSigningKeyFailed(AutogramException exception) {
        throw unavailable();
    }

    @Override
    public void onSigningSuccess(SigningJob job) {
        throw unavailable();
    }

    @Override
    public void onSigningFailed(AutogramException exception, SigningJob job) {
        throw unavailable();
    }

    @Override
    public void onSigningFailed(AutogramException exception) {
        throw unavailable();
    }

    @Override
    public void onDocumentSaved(File targetFile) {
        throw unavailable();
    }

    @Override
    public void onDocumentBatchSaved(BatchUiResult result) {
        throw unavailable();
    }

    @Override
    public void onWorkThreadDo(Runnable callback) {
        throw unavailable();
    }

    @Override
    public void onUIThreadDo(Runnable callback) {
        throw unavailable();
    }

    @Override
    public void onUpdateAvailable() {
        throw unavailable();
    }

    @Override
    public void onAboutInfo() {
        throw unavailable();
    }

    @Override
    public void onPDFAComplianceCheckFailed(SigningJob job) {
        throw unavailable();
    }

    @Override
    public void onSignatureValidationCompleted(ValidationReports reports) {
        throw unavailable();
    }

    @Override
    public void onSignatureCheckCompleted(ValidationReports reports) {
        throw unavailable();
    }

    @Override
    public void showIgnorableExceptionDialog(IgnorableException exception) {
        throw unavailable();
    }

    @Override
    public void showError(AutogramException exception) {
        throw unavailable();
    }

    @Override
    public void updateBatch() {
        throw unavailable();
    }

    @Override
    public void resetSigningKey() {
        throw unavailable();
    }

    @Override
    public void consentCertificateReadingAndThen(Consumer<Runnable> callback, Runnable onCancel) {
        throw unavailable();
    }

    private static UnsupportedOperationException unavailable() {
        return new UnsupportedOperationException("Machine mode does not support interactive UI");
    }
}
