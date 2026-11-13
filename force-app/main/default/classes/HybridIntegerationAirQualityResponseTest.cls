@IsTest
private class HybridIntegerationAirQualityResponseTest {
    @IsTest
    static void deserializesAllSupportedFields() {
        HybridIntegerationAirQualityResponse r = HybridIntegerationAirQualityResponse.parse(HybridIntegerationTestSupport.airQualityJson('2026-07-01T14:30', 3600));
        Assert.areEqual(51.5, r.latitude);
        Assert.areEqual(-0.12, r.longitude);
        Assert.areEqual('Europe/London', r.timezone);
        Assert.areEqual(3600, r.utc_offset_seconds);
        Assert.areEqual('2026-07-01T14:30', r.current.time_x);
        Assert.areEqual(10.123, r.current.pm2_5);
        Assert.areEqual(20.456, r.current.pm10);
        Assert.areEqual(42, r.current.us_aqi);
        Assert.areEqual(35, r.current.european_aqi);
        Assert.areEqual(55.5, r.current.ozone);
        Assert.areEqual(18.0, r.current.nitrogen_dioxide);
        Assert.isTrue(r.hasCurrentData());
    }

    @IsTest
    static void nullMeasurementsAreAllowed() {
        String json = '{"utc_offset_seconds":0,"current":{"time":"2026-11-12T14:30","pm10":null,"pm2_5":9.5,"us_aqi":null}}';
        HybridIntegerationAirQualityResponse r = HybridIntegerationAirQualityResponse.parse(json);
        Assert.isNull(r.current.pm10);
        Assert.isNull(r.current.us_aqi);
        Assert.areEqual(9.5, r.current.pm2_5);
        Assert.isTrue(r.hasCurrentData());
    }

    @IsTest
    static void currentWithOnlyNullMeasurementsIsNotUsable() {
        HybridIntegerationAirQualityResponse r = HybridIntegerationAirQualityResponse.parse('{"current":{"time":"2026-11-12T14:30","pm10":null}}');
        Assert.isFalse(r.hasCurrentData());
    }

    @IsTest
    static void missingCurrentBlockIsDetected() {
        Assert.isFalse(HybridIntegerationAirQualityResponse.parse('{"latitude":1,"longitude":2}').hasCurrentData());
    }

    @IsTest
    static void emptyBodyThrows() {
        assertCode('', HybridIntegerationIntegrationException.EMPTY_RESPONSE);
        assertCode(null, HybridIntegerationIntegrationException.EMPTY_RESPONSE);
    }

    @IsTest
    static void malformedJsonThrows() {
        assertCode('{"current": {', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('not json', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('null', HybridIntegerationIntegrationException.MALFORMED_JSON);
    }

    private static void assertCode(String body, String expected) {
        try {
            HybridIntegerationAirQualityResponse.parse(body);
            Assert.fail('Expected exception ' + expected);
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(expected, e.errorCode);
        }
    }
}
