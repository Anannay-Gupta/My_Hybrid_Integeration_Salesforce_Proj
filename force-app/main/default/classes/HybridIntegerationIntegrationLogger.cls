/**
 * Writes Integration_Log__c rows. NEVER throws: a logging failure must not hide the original outcome.
 * Inserts in system mode on purpose, so audit rows are written even for users without Integration_Log__c access.
 * Never put credentials, tokens or headers into a LogEntry.
 */
public with sharing class HybridIntegerationIntegrationLogger {
    // Integration_Name__c picklist values. API_NINJAS_HOLIDAYS replaces Nager.Date and must exist in the picklist.
    public static final String OPEN_METEO_WEATHER     = 'Open-Meteo Weather';
    public static final String OPEN_METEO_AIR_QUALITY = 'Open-Meteo Air Quality';
    public static final String OPENAQ                 = 'OpenAQ';
    public static final String API_NINJAS_HOLIDAYS    = 'API Ninjas Holidays';
    public static final String SPOTIFY                = 'Spotify';
    public static final String FASTAPI                = 'FastAPI';

    private static final Set<String> SUPPORTED_INTEGRATIONS = new Set<String>{
        OPEN_METEO_WEATHER, OPEN_METEO_AIR_QUALITY, OPENAQ, API_NINJAS_HOLIDAYS, SPOTIFY, FASTAPI
    };

    public static final String METHOD_GET = 'GET';
    public static final String STATUS_SUCCESS = 'Success';
    public static final String STATUS_FAILED = 'Failed';

    public class LogEntry {
        /** Required. Use one of the integration name constants above. No default, so a new integration cannot be mislabelled. */
        public String integrationName;
        public Boolean success = false;
        public String endpoint;
        public String httpMethod = METHOD_GET;
        public Integer statusCode;
        public Datetime requestTime;
        public Datetime responseTime;
        public Long durationMs;
        public String errorMessage;
        public String correlationId;
        public String responseSummary;
        public Integer retryCount = 0;

        public LogEntry(String integrationName) {
            this.integrationName = integrationName;
        }
    }

    @TestVisible private static Boolean forceFailure = false;
    @TestVisible private static String lastLoggingError;

    /** @return the Integration_Log__c Id, or null if logging failed. */
    public static Id log(LogEntry entry) {
        if (entry == null) {
            return null;
        }
        try {
            if (forceFailure) {
                throw new HybridIntegerationIntegrationException(HybridIntegerationIntegrationException.UNEXPECTED, 'Forced logging failure', null);
            }
            if (!SUPPORTED_INTEGRATIONS.contains(entry.integrationName)) {
                throw new HybridIntegerationIntegrationException(
                    HybridIntegerationIntegrationException.UNEXPECTED,
                    'Unsupported integration name: ' + entry.integrationName,
                    null
                );
            }
            Datetime now = Datetime.now();
            Integration_Log__c row = new Integration_Log__c(
                Integeration_Name__c = entry.integrationName,
                Endpoint__c = truncate(entry.endpoint, 255),
                HTTP_Method__c = String.isBlank(entry.httpMethod) ? METHOD_GET : entry.httpMethod,
                Status_Code__c = entry.statusCode,
                Status__c = entry.success ? STATUS_SUCCESS : STATUS_FAILED,
                Request_Time__c = entry.requestTime == null ? now : entry.requestTime,
                Response_Time__c = entry.responseTime,
                Duration_ms__c = entry.durationMs,
                Error_Message__c = truncate(entry.errorMessage, 32000),
                Retry_Count__c = entry.retryCount,
                Correlation_ID__c = truncate(entry.correlationId, 100),
                Response_Summary__c = truncate(entry.responseSummary, 32000)
            );
            insert row;
            return row.Id;
        } catch (Exception e) {
            lastLoggingError = e.getTypeName() + ': ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, 'Integration_Log__c insert failed: ' + lastLoggingError);
            return null;
        }
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null || s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen);
    }
}
