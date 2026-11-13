@IsTest
private class HybridIntegerationAirQualityRepoTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void savesReadingAndReturnsId() {
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Air_Quality_Reading__c reading = HybridIntegerationAirQualityMapper.toReading(
            HybridIntegerationAirQualityResponse.parse(HybridIntegerationTestSupport.okAirQualityJson()), locId);
        Id savedId = HybridIntegerationAirQualityRepository.save(reading);
        Assert.isNotNull(savedId);
        Air_Quality_Reading__c row = [SELECT Location__c, Station__c, PM25__c, US_AQI__c, Data_Source__c, Measurement_Type__c
            FROM Air_Quality_Reading__c WHERE Id = :savedId];
        Assert.areEqual(locId, row.Location__c);
        Assert.isNull(row.Station__c);
        Assert.areEqual(10.12, row.PM25__c);
        Assert.areEqual(42, row.US_AQI__c);
        Assert.areEqual('Open-Meteo', row.Data_Source__c);
        Assert.areEqual('Forecast', row.Measurement_Type__c);
    }

    @IsTest
    static void databaseFailureIsWrapped() {
        // Lookup pointing at a Contact-prefix Id (wrong object) -> invalid cross reference on insert
        Air_Quality_Reading__c bad = new Air_Quality_Reading__c(Location__c = Id.valueOf('003000000000001'), PM10__c = 1);
        try {
            HybridIntegerationAirQualityRepository.save(bad);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.DML_FAILURE, e.errorCode);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Air_Quality_Reading__c]);
    }

    @IsTest
    static void nullReadingRejected() {
        try {
            HybridIntegerationAirQualityRepository.save(null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.DML_FAILURE, e.errorCode);
        }
    }

    @IsTest
    static void findLatestReturnsMostRecentByRecordedAt() {
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        insert new List<Air_Quality_Reading__c>{
            new Air_Quality_Reading__c(Location__c = locId, PM25__c = 1, Recorded_At__c = Datetime.newInstanceGmt(2026, 11, 10, 10, 0, 0)),
            new Air_Quality_Reading__c(Location__c = locId, PM25__c = 3, Recorded_At__c = Datetime.newInstanceGmt(2026, 11, 12, 10, 0, 0)),
            new Air_Quality_Reading__c(Location__c = locId, PM25__c = 2, Recorded_At__c = Datetime.newInstanceGmt(2026, 11, 11, 10, 0, 0))
        };
        Air_Quality_Reading__c latest = HybridIntegerationAirQualityRepository.findLatestForLocation(locId);
        Assert.areEqual(3, latest.PM25__c);
    }

    @IsTest
    static void findLatestReturnsNullWhenNone() {
        Assert.isNull(HybridIntegerationAirQualityRepository.findLatestForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID)));
    }
}
