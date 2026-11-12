@IsTest
private class HybridIntegerationWeatherRepositoryTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void savesSnapshotAndReturnsId() {
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Weather_Snapshot__c snap = HybridIntegerationWeatherMapper.toSnapshot(HybridIntegerationWeatherResponse.parse(HybridIntegerationTestSupport.okJson()), locId);
        Id savedId = HybridIntegerationWeatherRepository.save(snap);
        Assert.isNotNull(savedId);
        Weather_Snapshot__c row = [SELECT Location__c, Temperature__c, Forecast_Type__c, Data_Source__c FROM Weather_Snapshot__c WHERE Id = :savedId];
        Assert.areEqual(locId, row.Location__c);
        Assert.areEqual(12.35, row.Temperature__c);
        Assert.areEqual('Current', row.Forecast_Type__c);
        Assert.areEqual('Open-Meteo', row.Data_Source__c);
    }

    @IsTest
    static void databaseFailureIsWrapped() {
        // Lookup pointing at a Contact-prefix Id (wrong object) -> insert fails with an invalid cross reference error
        Weather_Snapshot__c bad = new Weather_Snapshot__c(Location__c = Id.valueOf('003000000000001'), Temperature__c = 1);
        try {
            HybridIntegerationWeatherRepository.save(bad);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.DML_FAILURE, e.errorCode);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Weather_Snapshot__c]);
    }

    @IsTest
    static void nullSnapshotRejected() {
        try {
            HybridIntegerationWeatherRepository.save(null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.DML_FAILURE, e.errorCode);
        }
    }
}
