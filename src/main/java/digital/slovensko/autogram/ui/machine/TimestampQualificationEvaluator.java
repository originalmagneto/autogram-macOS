package digital.slovensko.autogram.ui.machine;

import eu.europa.esig.dss.enumerations.TimestampQualification;
import eu.europa.esig.dss.simplereport.SimpleReport;

public final class TimestampQualificationEvaluator {
    public boolean hasValidQualifiedTimestamp(SimpleReport report, String signatureId) {
        return report.getSignatureTimestamps(signatureId).stream().anyMatch(timestamp ->
                report.isValid(timestamp.getId())
                        && report.getTimestampQualification(timestamp.getId()) == TimestampQualification.QTSA);
    }
}
