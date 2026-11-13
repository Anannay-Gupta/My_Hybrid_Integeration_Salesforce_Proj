@IsTest
private class HybridIntegerationAirQualityServiceTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void successfulCallReturnsTypedResultAndBuildsEncodedEndpoint() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okAirQualityJson()));
        HybridIntegerationWeatherService.CallContext ctx = new HybridIntegerationWeatherService.CallContext();
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Test.startTest();
        HybridIntegerationAirQualityService.AirQualityResult r = HybridIntegerationAirQualityService.fetchForLocation(locId, ctx);
        Test.stopTest();

        Assert.areEqual(locId, r.locationId);
        Assert.areEqual(10.123, r.airQuality.current.pm2_5);
        Assert.areEqual(200, ctx.statusCode);
        Assert.isNotNull(ctx.requestTime);
        Assert.isNotNull(ctx.responseTime);
        Assert.isNotNull(ctx.durationMs);
        Assert.isTrue(ctx.responseSummary.contains('pm2_5=10.123'));

        String ep = HybridIntegerationTestSupport.lastRequest.getEndpoint();
        Assert.isTrue(ep.startsWith('callout:Hybrid_Integeration_Air_Quality/v1/air-quality?'), ep);
        Assert.isTrue(ep.contains('latitude=51.507400'), ep);
        Assert.isTrue(ep.contains('longitude=-0.127800'), ep);
        Assert.isTrue(ep.contains('current=pm2_5%2Cpm10%2Cus_aqi%2Ceuropean_aqi%2Cozone%2Cnitrogen_dioxide'), ep);
        Assert.isTrue(ep.contains('timezone=auto'), ep);
        Assert.areEqual('GET', HybridIntegerationTestSupport.lastRequest.getMethod());
    }

    @IsTest
    static void coordinatesOverloadWorks() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okAirQualityJson()));
        Test.startTest();
        HybridIntegerationAirQualityService.AirQualityResult r = HybridIntegerationAirQualityService.fetchForCoordinates(48.8566, 2.3522);
        Test.stopTest();
        Assert.isNotNull(r.airQuality);
        Assert.isNull(r.locationId);
    }

    @IsTest
    static void invalidCoordinatesRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        expect(91, 0, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        expect(0, 181, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        expect(null, 0, null, HybridIntegerationIntegrationException.NULL_COORDINATES);
        expect(0, null, null, HybridIntegerationIntegrationException.NULL_COORDINATES);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void storedBadOrNullCoordinatesRejected() {
        HybridIntegerationTestSupport.reset();
        assertLocationError(HybridIntegerationTestSupport.LOC_BAD_LAT, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        assertLocationError(HybridIntegerationTestSupport.LOC_BAD_LON, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        assertLocationError(HybridIntegerationTestSupport.LOC_NULL, HybridIntegerationIntegrationException.NULL_COORDINATES);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void missingLocationRejected() {
        for (Id badId : new List<Id>{ HybridIntegerationTestSupport.missingLocationId(), null }) {
            try {
                HybridIntegerationAirQualityService.fetchForLocation(badId);
                Assert.fail('Expected exception');
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, e.errorCode);
            }
        }
    }

    @IsTest static void http400() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(400, '{"error":true,"reason":"bad"}'), HybridIntegerationIntegrationException.HTTP_BAD_REQUEST);
    }
    @IsTest static void http401() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(401, '{}'), HybridIntegerationIntegrationException.HTTP_AUTH);
    }
    @IsTest static void http403() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(403, '{}'), HybridIntegerationIntegrationException.HTTP_AUTH);
    }
    @IsTest static void http429() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(429, '{"reason":"Too many requests"}'), HybridIntegerationIntegrationException.HTTP_RATE_LIMIT);
    }
    @IsTest static void http500() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(500, 'Internal Server Error'), HybridIntegerationIntegrationException.HTTP_SERVER_ERROR);
    }
    @IsTest static void unexpectedStatus() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(302, ''), HybridIntegerationIntegrationException.HTTP_UNEXPECTED);
    }
    @IsTest static void malformedJson() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(200, '{"current": {'), HybridIntegerationIntegrationException.MALFORMED_JSON);
    }
    @IsTest static void emptyResponse() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(200, ''), HybridIntegerationIntegrationException.EMPTY_RESPONSE);
    }
    @IsTest static void missingCurrentMeasurements() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(200, '{"latitude":10,"longitude":10,"utc_offset_seconds":0}'), HybridIntegerationIntegrationException.MISSING_CURRENT);
    }
    @IsTest static void timeout() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock('Read timed out'), HybridIntegerationIntegrationException.TIMEOUT);
    }
    @IsTest static void calloutException() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock('Connection refused'), HybridIntegerationIntegrationException.CALLOUT_FAILED);
    }

    @IsTest
    static void failureStillPopulatesCallContext() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(429, '{"reason":"slow down"}'));
        HybridIntegerationWeatherService.CallContext ctx = new HybridIntegerationWeatherService.CallContext();
        Test.startTest();
        try {
            HybridIntegerationAirQualityService.fetchForCoordinates(10, 10, ctx);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(429, e.httpStatus);
        }
        Test.stopTest();
        Assert.areEqual(429, ctx.statusCode);
        Assert.isNotNull(ctx.requestTime);
        Assert.isNotNull(ctx.durationMs);
        Assert.isTrue(ctx.responseSummary.contains('slow down'));
    }

    private static void assertLocationError(String locationName, String expectedCode) {
        try {
            HybridIntegerationAirQualityService.fetchForLocation(HybridIntegerationTestSupport.locationId(locationName));
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(expectedCode, e.errorCode);
        }
    }

    // Callout tests (mock supplied) run once per method, so startTest/stopTest is safe and resets the
    // uncommitted-work state left by @TestSetup. Validation-only tests (mock == null) call this several times
    // and never call out.
    private static void expect(Decimal lat, Decimal lon, HybridIntegerationTestSupport.Mock mock, String expectedCode) {
        Boolean isCalloutTest = mock != null;
        if (isCalloutTest) {
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
        }
        Boolean thrown = false;
        try {
            HybridIntegerationAirQualityService.fetchForCoordinates(lat, lon);
        } catch (HybridIntegerationIntegrationException e) {
            thrown = true;
            Assert.areEqual(expectedCode, e.errorCode, e.getMessage());
            Assert.isNotNull(e.getSafeMessage());
        }
        if (isCalloutTest) {
            Test.stopTest();
        }
        Assert.isTrue(thrown, 'Expected ' + expectedCode);
    }
}
