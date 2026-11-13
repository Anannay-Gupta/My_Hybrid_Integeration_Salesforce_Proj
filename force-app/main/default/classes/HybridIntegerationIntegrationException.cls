/**
 * Reusable exception for integration failures (Open-Meteo Weather today; Air Quality, OpenAQ, ... later).
 * errorCode   : stable machine-readable code (used for logging / branching).
 * message     : internal, technical message (goes to Integration_Log__c only).
 * userMessage : safe, generic text that may be shown to LWC users.
 */
public class HybridIntegerationIntegrationException extends Exception {
    public static final String INVALID_COORDINATES = 'INVALID_COORDINATES';
    public static final String NULL_COORDINATES    = 'NULL_COORDINATES';
    public static final String LOCATION_NOT_FOUND  = 'LOCATION_NOT_FOUND';
    public static final String ACCESS_DENIED       = 'ACCESS_DENIED';
    public static final String HTTP_BAD_REQUEST    = 'HTTP_BAD_REQUEST';
    public static final String HTTP_AUTH           = 'HTTP_AUTH';
    public static final String HTTP_RATE_LIMIT     = 'HTTP_RATE_LIMIT';
    public static final String HTTP_SERVER_ERROR   = 'HTTP_SERVER_ERROR';
    public static final String HTTP_UNEXPECTED     = 'HTTP_UNEXPECTED';
    public static final String TIMEOUT             = 'TIMEOUT';
    public static final String CALLOUT_FAILED      = 'CALLOUT_FAILED';
    public static final String EMPTY_RESPONSE      = 'EMPTY_RESPONSE';
    public static final String MALFORMED_JSON      = 'MALFORMED_JSON';
    public static final String MISSING_CURRENT     = 'MISSING_CURRENT';
    public static final String INVALID_TIMESTAMP   = 'INVALID_TIMESTAMP';
    public static final String DML_FAILURE         = 'DML_FAILURE';
    public static final String UNEXPECTED          = 'UNEXPECTED';
    public static final String INVALID_COUNTRY     = 'INVALID_COUNTRY';
    public static final String INVALID_CATEGORY    = 'INVALID_CATEGORY';
    public static final String INVALID_RECORD      = 'INVALID_RECORD';
    public static final String QUOTA_EXCEEDED      = 'QUOTA_EXCEEDED';

    public String errorCode { get; private set; }
    public Integer httpStatus { get; private set; }
    public String userMessage { get; private set; }

    public HybridIntegerationIntegrationException(String errorCode, String message, String userMessage, Integer httpStatus) {
        this(message);
        this.errorCode = errorCode;
        this.userMessage = userMessage;
        this.httpStatus = httpStatus;
    }

    public HybridIntegerationIntegrationException(String errorCode, String message, String userMessage) {
        this(errorCode, message, userMessage, null);
    }

    /** Text that is safe to show to end users. */
    public String getSafeMessage() {
        return String.isBlank(userMessage) ? 'The request could not be completed.' : userMessage;
    }
}
