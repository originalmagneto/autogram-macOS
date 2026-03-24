package digital.slovensko.autogram.ui.gui;

import digital.slovensko.autogram.core.SigningKey;
import eu.europa.esig.dss.model.x509.CertificateToken;
import javafx.application.Platform;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.VBox;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import javax.security.auth.x500.X500Principal;
import java.math.BigInteger;
import java.security.Principal;
import java.security.PublicKey;
import java.security.cert.X509Certificate;
import java.util.Date;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class SigningDialogControllerTests {
    @BeforeAll
    static void initFxToolkit() throws InterruptedException {
        try {
            var latch = new CountDownLatch(1);
            Platform.startup(latch::countDown);
            latch.await(2, TimeUnit.SECONDS);
        } catch (IllegalStateException ignored) {
            // Toolkit already initialized.
        }
    }

    @Test
    void refreshSigningKeyWithoutSelectionKeepsCompactToolbar() throws InterruptedException {
        var gui = mock(GUI.class);
        when(gui.getActiveSigningKey()).thenReturn(null);

        var controller = createController(gui);
        runOnFxThreadAndWait(controller::refreshSigningKey);

        assertEquals("Podpísať dokument", controller.mainButton.getText());
        assertFalse(controller.changeKeyButton.isVisible());
        assertFalse(controller.changeKeyButton.isManaged());
        assertFalse(controller.activeCertificateLabel.isVisible());
        assertFalse(controller.activeCertificateLabel.isManaged());
    }

    @Test
    void refreshSigningKeyWithSelectionShowsCertificateChipAndChangeAction() throws InterruptedException {
        var gui = mock(GUI.class);
        when(gui.getActiveSigningKey()).thenReturn(createSigningKey("CN=Test User,OU=QA,O=Autogram", "Test User | QA"));

        var controller = createController(gui);
        runOnFxThreadAndWait(controller::refreshSigningKey);

        assertEquals("Podpísať dokument", controller.mainButton.getText());
        assertTrue(controller.changeKeyButton.isVisible());
        assertTrue(controller.changeKeyButton.isManaged());
        assertTrue(controller.activeCertificateLabel.isVisible());
        assertTrue(controller.activeCertificateLabel.isManaged());
        assertTrue(controller.activeCertificateLabel.getText().contains("Test User"));
        assertNotNull(controller.activeCertificateLabel.getTooltip());
        assertTrue(controller.activeCertificateLabel.getTooltip().getText().contains("Test User | QA"));
    }

    private static SigningDialogController createController(GUI gui) {
        var controller = new SigningDialogController(null, null, gui, "Dokument", false);
        controller.mainBox = new VBox();
        controller.mainButton = new Button();
        controller.changeKeyButton = new Button();
        controller.activeCertificateLabel = new Label();
        return controller;
    }

    private static SigningKey createSigningKey(String rfc2253, String displayText) {
        var certificateToken = new CertificateToken(
                new StubX509Certificate(new X500Principal(rfc2253), new X500Principal("CN=Issuer,O=Autogram")));

        return new SigningKey(null, null) {
            @Override
            public CertificateToken getCertificate() {
                return certificateToken;
            }

            @Override
            public String toString() {
                return displayText;
            }
        };
    }

    private static final class StubX509Certificate extends X509Certificate {
        private final X500Principal subject;
        private final X500Principal issuer;

        private StubX509Certificate(X500Principal subject, X500Principal issuer) {
            this.subject = subject;
            this.issuer = issuer;
        }

        @Override
        public void checkValidity() {
        }

        @Override
        public void checkValidity(Date date) {
        }

        @Override
        public int getVersion() {
            return 3;
        }

        @Override
        public BigInteger getSerialNumber() {
            return BigInteger.ONE;
        }

        @Override
        public Principal getIssuerDN() {
            return issuer;
        }

        @Override
        public Principal getSubjectDN() {
            return subject;
        }

        @Override
        public Date getNotBefore() {
            return new Date(0);
        }

        @Override
        public Date getNotAfter() {
            return new Date(Long.MAX_VALUE);
        }

        @Override
        public byte[] getTBSCertificate() {
            return new byte[0];
        }

        @Override
        public byte[] getSignature() {
            return new byte[0];
        }

        @Override
        public String getSigAlgName() {
            return "SHA256withRSA";
        }

        @Override
        public String getSigAlgOID() {
            return "1.2.840.113549.1.1.11";
        }

        @Override
        public byte[] getSigAlgParams() {
            return new byte[0];
        }

        @Override
        public boolean[] getIssuerUniqueID() {
            return null;
        }

        @Override
        public boolean[] getSubjectUniqueID() {
            return null;
        }

        @Override
        public boolean[] getKeyUsage() {
            return null;
        }

        @Override
        public int getBasicConstraints() {
            return -1;
        }

        @Override
        public byte[] getEncoded() {
            return new byte[0];
        }

        @Override
        public void verify(PublicKey key) {
        }

        @Override
        public void verify(PublicKey key, String sigProvider) {
        }

        @Override
        public String toString() {
            return subject.getName();
        }

        @Override
        public PublicKey getPublicKey() {
            return null;
        }

        @Override
        public boolean hasUnsupportedCriticalExtension() {
            return false;
        }

        @Override
        public Set<String> getCriticalExtensionOIDs() {
            return null;
        }

        @Override
        public Set<String> getNonCriticalExtensionOIDs() {
            return null;
        }

        @Override
        public byte[] getExtensionValue(String oid) {
            return null;
        }

        @Override
        public X500Principal getSubjectX500Principal() {
            return subject;
        }

        @Override
        public X500Principal getIssuerX500Principal() {
            return issuer;
        }
    }

    private static void runOnFxThreadAndWait(Runnable runnable) throws InterruptedException {
        var done = new CountDownLatch(1);
        var error = new AtomicReference<Throwable>();
        Platform.runLater(() -> {
            try {
                runnable.run();
            } catch (Throwable t) {
                error.set(t);
            } finally {
                done.countDown();
            }
        });
        done.await(2, TimeUnit.SECONDS);
        if (error.get() != null) {
            throw new AssertionError(error.get());
        }
    }
}
