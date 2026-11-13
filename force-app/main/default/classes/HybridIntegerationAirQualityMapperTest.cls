@IsTest
private class HybridIntegerationAirQualityMapperTest {
    @IsTest
    static void mapsAllConfirmedFields() {
        HybridIntegerationAirQualityResponse dto = HybridIntegerationAirQualityResponse.parse(HybridIntegerationTestSupport.airQualityJson('2026-11-12T14:30', 0));
        Id locId = HybridIntegerationTestSupport.missingLocationId();
        Air_Quality_Reading__c r = HybridIntegerationAirQualityMapper.toReading(dto, locId);
        Assert.areEqual(locId, r.Location__c);
        Assert.areEqual(10.12, r.PM25__c, 'PM2.5 rounded HALF_UP to 2dp');
        Assert.areEqual(20.46, r.PM10__c, 'PM10 rounded HALF_UP to 2dp');
        Assert.areEqual(42, r.US_AQI__c);
        Assert.areEqual(35, r.European_AQI__c);
        Assert.areEqual(55.50, r.Ozone__c);
        Assert.areEqual(18.00, r.Nitrogen_Dioxide__c);
        Assert.areEqual('Open-Meteo', r.Data_Source__c);
        Assert.areEqual('Forecast', r.Measurement_Type__c);
        Assert.isNull(r.Station__c, 'Station must stay empty for coordinate-based data');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 12, 14, 30, 0), r.Recorded_At__c);
    }

    @IsTest
    static void timestampHonoursUtcOffset() {
        HybridIntegerationAirQualityResponse dto = HybridIntegerationAirQualityResponse.parse(HybridIntegerationTestSupport.airQualityJson('2026-07-01T14:30', 3600));
        Air_Quality_Reading__c r = HybridIntegerationAirQualityMapper.toReading(dto, HybridIntegerationTestSupport.missingLocationId());
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 1, 13, 30, 0), r.Recorded_At__c);
    }

    @IsTest
    static void fractionalAqiIsRoundedHalfUpNotTruncated() {
        String json = HybridIntegerationTestSupport.okAirQualityJson().replace('"us_aqi":42', '"us_aqi":42.6').replace('"european_aqi":35', '"european_aqi":34.4');
        Air_Quality_Reading__c r = HybridIntegerationAirQualityMapper.toReading(HybridIntegerationAirQualityResponse.parse(json), HybridIntegerationTestSupport.missingLocationId());
        Assert.areEqual(43, r.US_AQI__c);
        Assert.areEqual(34, r.European_AQI__c);
    }

    @IsTest
    static void nullMeasurementsStayNull() {
        HybridIntegerationAirQualityResponse dto = HybridIntegerationAirQualityResponse.parse('{"utc_offset_seconds":0,"current":{"time":"2026-11-12T14:30","pm2_5":5.5}}');
        Air_Quality_Reading__c r = HybridIntegerationAirQualityMapper.toReading(dto, HybridIntegerationTestSupport.missingLocationId());
        Assert.areEqual(5.50, r.PM25__c);
        Assert.isNull(r.PM10__c);
        Assert.isNull(r.US_AQI__c);
        Assert.isNull(r.European_AQI__c);
        Assert.isNull(r.Ozone__c);
        Assert.isNull(r.Nitrogen_Dioxide__c);
    }

    @IsTest
    static void nullInputsThrow() {
        try {
            HybridIntegerationAirQualityMapper.toReading(null, HybridIntegerationTestSupport.missingLocationId());
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.MISSING_CURRENT, e.errorCode);
        }
        try {
            HybridIntegerationAirQualityMapper.toReading(HybridIntegerationAirQualityResponse.parse(HybridIntegerationTestSupport.okAirQualityJson()), null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, e.errorCode);
        }
    }
}
