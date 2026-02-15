package digital.slovensko.autogram.util;

import eu.europa.esig.dss.enumerations.MimeTypeEnum;
import eu.europa.esig.dss.model.DSSDocument;
import eu.europa.esig.dss.pades.exception.InvalidPasswordException;
import eu.europa.esig.dss.pdf.pdfbox.PdfBoxDocumentReader;

public class PDFUtils {
    public static boolean isPdfAndPasswordProtected(DSSDocument document) {
        if (document.getMimeType().equals(MimeTypeEnum.PDF)) {
            try (PdfBoxDocumentReader reader = new PdfBoxDocumentReader(document)) {
                // Success
            } catch (InvalidPasswordException e) {
                return true;
            } catch (Exception e) {
                // Handle IOException, EOFException, etc. gracefully
            }
        }
        return false;
    }

    public static int getPageCount(DSSDocument document) {
        if (document.getMimeType().equals(MimeTypeEnum.PDF)) {
            try (PdfBoxDocumentReader reader = new PdfBoxDocumentReader(document)) {
                return (int) reader.getNumberOfPages();
            } catch (Exception e) {
                // Return 0 if error occurred (EOFException, malformed PDF, etc.)
                return 0;
            }
        }
        return -1;
    }
}
