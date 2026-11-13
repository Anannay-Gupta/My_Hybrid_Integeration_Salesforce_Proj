/**
 * Apex entry point (future LWC). Thin orchestration: service (callouts) -> mapper -> repository (DML) -> logger.
 * Never throws to the client. Request logs are written after all callouts and after the upsert.
 * Requests rejected before any callout (invalid input, quota) are NOT logged: Integration_Log__c rows are the quota
 * counter, so logging non-requests would inflate it.
 */
public with sharing class HybridIntegerationHolidayController {

    public class HolidayApiResponse {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String message;
        @AuraEnabled public String errorCode;
        @AuraEnabled public String correlationId;
        @AuraEnabled public String countryCode;
        @AuraEnabled public String holidayType;
        @AuraEnabled public Integer requestCount = 0;
        @AuraEnabled public Integer retrievedCount = 0;
        @AuraEnabled public Integer mappedCount = 0;
        @AuraEnabled public Integer skippedCount = 0;
        @AuraEnabled public Integer duplicateCount = 0;
        @AuraEnabled public Integer savedCount = 0;
        @AuraEnabled public Integer insertedCount = 0;
        @AuraEnabled public Integer updatedCount = 0;
        @AuraEnabled public Integer failedCount = 0;
        @AuraEnabled public Integer monthlyRequestsUsedBefore;
        @AuraEnabled public Integer monthlyRequestThreshold;
        @AuraEnabled public List<String> errors = new List<String>();
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<Id> logIds = new List<Id>();
    }

    @AuraEnabled
    public static HolidayApiResponse fetchAndSaveHolidays(String countryCode, String holidayType) {
        HolidayApiResponse out = new HolidayApiResponse();
        out.countryCode = countryCode;
        out.holidayType = holidayType;
        out.correlationId = EncodingUtil.convertToHex(Crypto.generateAesKey(128));

        HybridIntegerationHolidayService.FetchResult fetch = new HybridIntegerationHolidayService.FetchResult();
        try {
            // 1) quota SOQL + callouts (no DML yet)
            HybridIntegerationHolidayService.fetchHolidays(countryCode, holidayType, out.correlationId, fetch);
            out.countryCode = fetch.countryCode;
            out.holidayType = fetch.holidayCategory;
            out.retrievedCount = fetch.holidays.size();

            // 2) pure mapping, then DML
            HybridIntegerationHolidayMapper.MappingResult mapped = HybridIntegerationHolidayMapper.toHolidays(fetch.holidays, fetch.holidayCategory);
            out.mappedCount = mapped.records.size();
            out.skippedCount = mapped.skippedCount;
            out.duplicateCount = mapped.duplicateCount;
            out.warnings = mapped.warnings;

            HybridIntegerationHolidayRepository.UpsertSummary saved = HybridIntegerationHolidayRepository.upsertHolidays(mapped.records);
            out.insertedCount = saved.insertedCount;
            out.updatedCount = saved.updatedCount;
            out.savedCount = saved.savedCount();
            out.failedCount = saved.failedCount;
            out.errors = saved.errors;

            if (saved.failedCount > 0) {
                out.errorCode = HybridIntegerationIntegrationException.DML_FAILURE;
                out.message = saved.savedCount() + ' holidays saved, ' + saved.failedCount + ' failed.';
            } else {
                out.success = true;
                out.message = fetch.holidays.isEmpty()
                    ? 'No holidays were returned for this country and category.'
                    : out.savedCount + ' holidays saved (' + out.insertedCount + ' new, ' + out.updatedCount + ' updated).';
            }
        } catch (HybridIntegerationIntegrationException e) {
            out.errorCode = e.errorCode;
            out.message = e.getSafeMessage();
            if (e.errorCode == HybridIntegerationIntegrationException.DML_FAILURE || e.errorCode == HybridIntegerationIntegrationException.QUOTA_EXCEEDED) {
                out.errors.add(e.getMessage());
            }
        } catch (Exception e) {
            out.errorCode = HybridIntegerationIntegrationException.UNEXPECTED;
            out.message = 'An unexpected error occurred. Reference: ' + out.correlationId;
            System.debug(LoggingLevel.ERROR, 'fetchAndSaveHolidays failed: ' + e.getTypeName() + ': ' + e.getMessage());
        }

        out.requestCount = fetch.requests.size();
        out.monthlyRequestsUsedBefore = fetch.monthlyRequestsUsedBefore;
        out.monthlyRequestThreshold = fetch.safetyThreshold;

        // 3) log every attempted request (DML after all callouts; the logger never throws)
        for (HybridIntegerationHolidayService.RequestRecord rec : fetch.requests) {
            HybridIntegerationIntegrationLogger.LogEntry entry =
                new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);
            entry.success = rec.success;
            entry.endpoint = rec.context.endpoint;
            entry.httpMethod = rec.context.httpMethod;
            entry.statusCode = rec.context.statusCode;
            entry.requestTime = rec.context.requestTime;
            entry.responseTime = rec.context.responseTime;
            entry.durationMs = rec.context.durationMs;
            entry.errorMessage = rec.errorMessage;
            entry.correlationId = out.correlationId;
            entry.responseSummary = rec.context.responseSummary;
            Id logId = HybridIntegerationIntegrationLogger.log(entry);
            if (logId != null) {
                out.logIds.add(logId);
            }
        }
        return out;
    }
}
