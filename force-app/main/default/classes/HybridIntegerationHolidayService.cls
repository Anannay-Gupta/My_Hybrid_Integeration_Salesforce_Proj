/**
 * API Ninjas holidays callout orchestration, including the monthly quota check. No holiday DML.
 * Reuses HttpClient, IntegrationException and WeatherService.CallContext (shared data holder).
 * Callouts only: request logs are collected in memory (RequestRecord) and written by the caller AFTER the last
 * callout, because Apex forbids a callout after DML in the same transaction.
 * Fail-fast: the first failing request stops the run (no partial results are returned).
 */
public with sharing class HybridIntegerationHolidayService {
    public static final String NAMED_CREDENTIAL = 'Hybrid_Integration_Holidays';
    public static final String HOLIDAYS_PATH = '/v2/holidays';
    public static final Integer MONTHLY_REQUEST_LIMIT = 3000;
    public static final Integer DEFAULT_SAFETY_THRESHOLD = 2700;
    public static final Integer TIMEOUT_MS = 10000;

    @TestVisible private static Integer safetyThreshold = DEFAULT_SAFETY_THRESHOLD;

    /** One attempted API request (successful or not). */
    public class RequestRecord {
        public String apiType;
        public HybridIntegerationWeatherService.CallContext context = new HybridIntegerationWeatherService.CallContext();
        public Boolean success = false;
        public String errorMessage;
        public Integer returnedCount = 0;
        public HybridIntegerationHolidayResponse parsed;

        public RequestRecord(String apiType) {
            this.apiType = apiType;
        }
    }

    public class FetchResult {
        public String countryCode;
        public String holidayCategory;
        public Integer monthlyRequestsUsedBefore;
        public Integer safetyThreshold;
        public List<RequestRecord> requests = new List<RequestRecord>();
        public List<HybridIntegerationHolidayResponse.Holiday> holidays = new List<HybridIntegerationHolidayResponse.Holiday>();
    }

    /** Fills the supplied result progressively so the caller can still log attempted requests if this throws. */
    public static void fetchHolidays(String countryCode, String holidayCategory, String correlationId, FetchResult result) {
        result.countryCode = normalizeCountry(countryCode);
        result.holidayCategory = HybridIntegerationHolidayMapper.normalizeCategory(holidayCategory);
        List<String> apiTypes = HybridIntegerationHolidayMapper.apiTypesFor(result.holidayCategory);

        result.safetyThreshold = safetyThreshold;
        result.monthlyRequestsUsedBefore = countRequestsThisMonth();
        assertQuotaAvailable(result.monthlyRequestsUsedBefore, apiTypes.size());

        for (String apiType : apiTypes) {
            RequestRecord rec = new RequestRecord(apiType);
            result.requests.add(rec);
            rec.context.correlationId = correlationId;
            executeRequest(result.countryCode, rec);
            // executeRequest throws on failure; reaching here means success
            result.holidays.addAll(rec.parsed.holidays);
        }
    }

    public static String normalizeCountry(String countryCode) {
        if (String.isBlank(countryCode) || !Pattern.matches('[A-Za-z]{2}', countryCode.trim())) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.INVALID_COUNTRY,
                'Country code must be 2 letters (ISO 3166-1 alpha-2), got: ' + countryCode,
                'Please provide a valid 2-letter country code.'
            );
        }
        return countryCode.trim().toUpperCase();
    }

    public static String buildEndpoint(String countryCode, String apiType) {
        // The year parameter is intentionally never sent: the free plan defaults to the current year.
        return 'callout:' + NAMED_CREDENTIAL + HOLIDAYS_PATH
            + '?country=' + EncodingUtil.urlEncode(countryCode, 'UTF-8')
            + '&type=' + EncodingUtil.urlEncode(apiType, 'UTF-8');
    }

    // ---- quota -------------------------------------------------------------------------------------

    /**
     * Counts this calendar month's (UTC) Integration_Log__c rows for API Ninjas, org-wide.
     * Limitation: log-based, not an atomic reservation. Concurrent transactions can each pass the check before
     * either writes its logs, so the threshold (2,700 of 3,000) is a safety margin, not a guarantee.
     */
    public static Integer countRequestsThisMonth() {
        Datetime now = Datetime.now();
        Datetime monthStart = Datetime.newInstanceGmt(now.yearGmt(), now.monthGmt(), 1);
        return new QuotaReader().count(monthStart, monthStart.addMonths(1));
    }

    public static void assertQuotaAvailable(Integer usedThisMonth, Integer requestsNeeded) {
        if (usedThisMonth + requestsNeeded > safetyThreshold) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.QUOTA_EXCEEDED,
                'Quota check failed: ' + usedThisMonth + ' used this month + ' + requestsNeeded + ' needed > threshold '
                    + safetyThreshold + ' (plan limit ' + MONTHLY_REQUEST_LIMIT + ').',
                'The monthly holiday request limit has been reached. Please try again next month.'
            );
        }
    }

    // Quota is org-wide, so the count must ignore record sharing. Only a number leaves this class.
    private without sharing class QuotaReader {
        public Integer count(Datetime fromInclusive, Datetime toExclusive) {
            String integrationName = HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS;
            return [
                SELECT COUNT()
                FROM Integration_Log__c
                WHERE Integeration_Name__c = :integrationName
                AND Request_Time__c >= :fromInclusive
                AND Request_Time__c < :toExclusive
            ];
        }
    }

    // ---- single request ----------------------------------------------------------------------------

    private static void executeRequest(String countryCode, RequestRecord rec) {
        HybridIntegerationWeatherService.CallContext ctx = rec.context;
        ctx.endpoint = buildEndpoint(countryCode, rec.apiType);
        ctx.requestTime = Datetime.now();
        Long startMs = System.currentTimeMillis();
        try {
            HttpResponse res;
            try {
                res = HybridIntegerationHttpClient.send(ctx.endpoint, ctx.httpMethod,
                    new Map<String, String>{ 'Accept' => 'application/json' }, TIMEOUT_MS);
            } finally {
                ctx.responseTime = Datetime.now();
                ctx.durationMs = System.currentTimeMillis() - startMs;
            }
            ctx.statusCode = res.getStatusCode();
            String body = res.getBody();
            ctx.responseSummary = truncate(body, 500);

            validateStatus(res.getStatusCode(), body);
            rec.parsed = HybridIntegerationHolidayResponse.parse(body);
            rec.returnedCount = rec.parsed.holidays.size();
            rec.success = true;
            ctx.responseSummary = 'country=' + countryCode + '; type=' + rec.apiType + '; returned=' + rec.returnedCount;
        } catch (HybridIntegerationIntegrationException e) {
            rec.errorMessage = e.errorCode + ': ' + e.getMessage();
            if (ctx.statusCode == null) {
                ctx.statusCode = e.httpStatus;
            }
            throw e;
        }
    }

    // NOTE: third copy of the HTTP status mapping (Weather, Air Quality, here). Candidate for a shared class.
    private static void validateStatus(Integer status, String body) {
        if (status == 200) {
            return;
        }
        String reason = extractReason(body);
        String detail = 'API Ninjas returned HTTP ' + status + (reason == null ? '' : ': ' + reason);
        String code;
        String userMsg;
        if (status == 400) {
            code = HybridIntegerationIntegrationException.HTTP_BAD_REQUEST;
            userMsg = 'The holidays request was rejected as invalid.';
        } else if (status == 401 || status == 403) {
            code = HybridIntegerationIntegrationException.HTTP_AUTH;
            userMsg = 'The holidays service denied access. Please contact your administrator.';
        } else if (status == 429) {
            code = HybridIntegerationIntegrationException.HTTP_RATE_LIMIT;
            userMsg = 'The holidays service is rate limiting requests. Please try again later.';
        } else if (status >= 500) {
            code = HybridIntegerationIntegrationException.HTTP_SERVER_ERROR;
            userMsg = 'The holidays service is currently unavailable. Please try again later.';
        } else {
            code = HybridIntegerationIntegrationException.HTTP_UNEXPECTED;
            userMsg = 'The holidays service returned an unexpected response.';
        }
        throw new HybridIntegerationIntegrationException(code, detail, userMsg, status);
    }

    // API Ninjas errors look like {"error": "..."}
    private static String extractReason(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> asMap = (Map<String, Object>) parsed;
                Object reason = asMap.containsKey('error') ? asMap.get('error') : asMap.get('reason');
                return reason == null ? null : truncate(String.valueOf(reason), 300);
            }
        } catch (Exception e) {
            // not JSON
        }
        return null;
    }

    private static String truncate(String s, Integer maxLen) {
        return (s == null || s.length() <= maxLen) ? s : s.substring(0, maxLen);
    }
}
