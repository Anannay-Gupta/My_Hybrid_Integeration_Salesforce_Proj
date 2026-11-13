/**
 * Bulk-safe upsert of Public_Holiday__c on External_Holiday_ID__c. User mode (CRUD/FLS enforced).
 * Never deletes records. Partial failures are reported per record (allOrNone = false).
 */
public with sharing class HybridIntegerationHolidayRepository {
    public static final Integer MAX_ERRORS = 20;

    public class UpsertSummary {
        public Integer insertedCount = 0;
        public Integer updatedCount = 0;
        public Integer failedCount = 0;
        public List<String> errors = new List<String>();

        public Integer savedCount() {
            return insertedCount + updatedCount;
        }
    }

    public static UpsertSummary upsertHolidays(List<Public_Holiday__c> records) {
        UpsertSummary summary = new UpsertSummary();
        if (records == null || records.isEmpty()) {
            return summary;
        }
        List<Database.UpsertResult> results;
        try {
            results = Database.upsert(records, Public_Holiday__c.External_Holiday_ID__c, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.DML_FAILURE,
                'Public_Holiday__c upsert failed (' + e.getTypeName() + '): ' + e.getMessage(),
                'The holidays were retrieved but could not be saved.'
            );
        }
        for (Integer i = 0; i < results.size(); i++) {
            Database.UpsertResult result = results[i];
            if (result.isSuccess()) {
                if (result.isCreated()) {
                    summary.insertedCount++;
                } else {
                    summary.updatedCount++;
                }
            } else {
                summary.failedCount++;
                if (summary.errors.size() < MAX_ERRORS) {
                    List<String> messages = new List<String>();
                    for (Database.Error err : result.getErrors()) {
                        messages.add(err.getStatusCode() + ': ' + err.getMessage());
                    }
                    summary.errors.add(records[i].Name + ' (' + records[i].Holiday_Date__c + '): ' + String.join(messages, '; '));
                }
            }
        }
        return summary;
    }
}
