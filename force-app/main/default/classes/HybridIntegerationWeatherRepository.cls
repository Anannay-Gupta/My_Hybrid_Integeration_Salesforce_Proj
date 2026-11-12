/**
 * Persistence for Weather_Snapshot__c.
 * Runs in user mode (CRUD/FLS enforced). No duplicate prevention: no reliable unique key exists
 * (see docs/integrations/weather-integration.md for the recommendation).
 */
public with sharing class HybridIntegerationWeatherRepository {
    public static Id save(Weather_Snapshot__c snapshot) {
        if (snapshot == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.DML_FAILURE,
                'Cannot save a null Weather_Snapshot__c.',
                'The weather data could not be saved.'
            );
        }
        try {
            insert as user snapshot;
            return snapshot.Id;
        } catch (Exception e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.DML_FAILURE,
                'Weather_Snapshot__c insert failed (' + e.getTypeName() + '): ' + e.getMessage(),
                'The weather was retrieved but could not be saved.'
            );
        }
    }
}
