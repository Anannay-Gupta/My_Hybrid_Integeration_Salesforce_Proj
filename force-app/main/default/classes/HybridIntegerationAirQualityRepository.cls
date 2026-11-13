/**
 * Persistence for Air_Quality_Reading__c. User mode (CRUD/FLS enforced).
 * No duplicate prevention: the schema has no reliable unique key (see docs).
 */
public with sharing class HybridIntegerationAirQualityRepository {
    public static Id save(Air_Quality_Reading__c reading) {
        if (reading == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.DML_FAILURE,
                'Cannot save a null Air_Quality_Reading__c.',
                'The air quality data could not be saved.'
            );
        }
        try {
            insert as user reading;
            return reading.Id;
        } catch (Exception e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.DML_FAILURE,
                'Air_Quality_Reading__c insert failed (' + e.getTypeName() + '): ' + e.getMessage(),
                'The air quality data was retrieved but could not be saved.'
            );
        }
    }

    /** Latest saved reading for a location (by Recorded_At__c), or null if none. */
    public static Air_Quality_Reading__c findLatestForLocation(Id locationId) {
        List<Air_Quality_Reading__c> rows;
        try {
            rows = [
                SELECT Id, Location__c, PM25__c, PM10__c, US_AQI__c, European_AQI__c, Ozone__c,
                       Nitrogen_Dioxide__c, Recorded_At__c, Data_Source__c, Measurement_Type__c
                FROM Air_Quality_Reading__c
                WHERE Location__c = :locationId
                WITH USER_MODE
                ORDER BY Recorded_At__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.ACCESS_DENIED,
                'Air_Quality_Reading__c query failed (likely CRUD/FLS): ' + e.getMessage(),
                'You do not have access to air quality readings.'
            );
        }
        return rows.isEmpty() ? null : rows[0];
    }
}
