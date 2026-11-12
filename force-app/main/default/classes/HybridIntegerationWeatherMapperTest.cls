@IsTest
private class HybridIntegerationWeatherMapperTest {
    @IsTest
    static void mapsAllConfirmedFields() {
        HybridIntegerationWeatherResponse dto = HybridIntegerationWeatherResponse.parse(HybridIntegerationTestSupport.weatherJson('2026-11-12T14:30', 0));
        Id fakeLoc = HybridIntegerationTestSupport.missingLocationId();
        Weather_Snapshot__c s = HybridIntegerationWeatherMapper.toSnapshot(dto, fakeLoc);
        Assert.areEqual(fakeLoc, s.Location__c);
        Assert.areEqual(12.35, s.Temperature__c, 'HALF_UP rounding to 2 dp');
        Assert.areEqual(81.00, s.Humidity__c);
        Assert.areEqual(14.70, s.Wind_Speed__c);
        Assert.areEqual(0.00, s.Precipitation__c);
        Assert.areEqual('Current', s.Forecast_Type__c);
        Assert.areEqual('Open-Meteo', s.Data_Source__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 12, 14, 30, 0), s.Recorded_At__c);
    }

    @IsTest
    static void positiveOffsetConvertsLocalTimeToUtc() {
        // 14:30 local at UTC+1 is 13:30 UTC
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 1, 13, 30, 0),
            HybridIntegerationWeatherMapper.parseApiTime('2026-07-01T14:30', 3600));
    }

    @IsTest
    static void negativeOffsetCrossesDateBoundary() {
        // 22:00 local at UTC-5 is 03:00 UTC next day
        Assert.areEqual(Datetime.newInstanceGmt(2026, 1, 2, 3, 0, 0),
            HybridIntegerationWeatherMapper.parseApiTime('2026-01-01T22:00', -18000));
    }

    @IsTest
    static void nullMeasurementsStayNull() {
        HybridIntegerationWeatherResponse dto = new HybridIntegerationWeatherResponse();
        dto.utc_offset_seconds = 0;
        dto.current = new HybridIntegerationWeatherResponse.CurrentWeather();
        dto.current.time_x = '2026-11-12T14:30';
        dto.current.temperature_2m = 5.5;
        Weather_Snapshot__c s = HybridIntegerationWeatherMapper.toSnapshot(dto, HybridIntegerationTestSupport.missingLocationId());
        Assert.areEqual(5.50, s.Temperature__c);
        Assert.isNull(s.Humidity__c);
        Assert.isNull(s.Wind_Speed__c);
        Assert.isNull(s.Precipitation__c);
    }

    @IsTest
    static void invalidTimestampThrows() {
        for (String bad : new List<String>{ 'garbage', '2026-11-12', '' }) {
            try {
                HybridIntegerationWeatherMapper.parseApiTime(bad, 0);
                Assert.fail('Expected exception for ' + bad);
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.INVALID_TIMESTAMP, e.errorCode);
            }
        }
        try {
            HybridIntegerationWeatherMapper.parseApiTime('2026-11-12T14:30', null);
            Assert.fail('Expected exception for null offset');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.INVALID_TIMESTAMP, e.errorCode);
        }
    }

    @IsTest
    static void nullDtoOrLocationThrows() {
        try {
            HybridIntegerationWeatherMapper.toSnapshot(null, HybridIntegerationTestSupport.missingLocationId());
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.MISSING_CURRENT, e.errorCode);
        }
        try {
            HybridIntegerationWeatherMapper.toSnapshot(HybridIntegerationWeatherResponse.parse(HybridIntegerationTestSupport.okJson()), null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, e.errorCode);
        }
    }
}
