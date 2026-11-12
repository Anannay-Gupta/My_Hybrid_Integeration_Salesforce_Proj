@IsTest
private class HybridIntegerationWeatherResponseTest {
    @IsTest
    static void deserializesAllSupportedFields() {
        HybridIntegerationWeatherResponse r = HybridIntegerationWeatherResponse.parse(HybridIntegerationTestSupport.weatherJson('2026-07-01T14:30', 3600));
        Assert.areEqual(51.5, r.latitude);
        Assert.areEqual(-0.12, r.longitude);
        Assert.areEqual('Europe/London', r.timezone);
        Assert.areEqual(3600, r.utc_offset_seconds);
        Assert.areEqual('2026-07-01T14:30', r.current.time_x);
        Assert.areEqual(12.345, r.current.temperature_2m);
        Assert.areEqual(81, r.current.relative_humidity_2m);
        Assert.areEqual(0, r.current.precipitation);
        Assert.areEqual(14.7, r.current.wind_speed_10m);
        Assert.isTrue(r.hasCurrentData());
    }

    @IsTest
    static void emptyBodyThrows() {
        assertCode('', HybridIntegerationIntegrationException.EMPTY_RESPONSE);
        assertCode(null, HybridIntegerationIntegrationException.EMPTY_RESPONSE);
    }

    @IsTest
    static void malformedJsonThrows() {
        assertCode('{"latitude": 51.5, "current": {', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('not json at all', HybridIntegerationIntegrationException.MALFORMED_JSON);
    }

    @IsTest
    static void jsonNullDeserializesToNullAndThrows() {
        assertCode('null', HybridIntegerationIntegrationException.MALFORMED_JSON);
    }

    @IsTest
    static void missingCurrentBlockIsDetected() {
        HybridIntegerationWeatherResponse r = HybridIntegerationWeatherResponse.parse('{"latitude":1,"longitude":2,"utc_offset_seconds":0}');
        Assert.isFalse(r.hasCurrentData());
    }

    private static void assertCode(String body, String expected) {
        try {
            HybridIntegerationWeatherResponse.parse(body);
            Assert.fail('Expected exception ' + expected);
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(expected, e.errorCode);
        }
    }
}
