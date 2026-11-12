@IsTest
private class HybridIntegerationWeatherServiceTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void successfulCallReturnsTypedResultAndBuildsEncodedEndpoint() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okJson()));
        HybridIntegerationWeatherService.CallContext ctx = new HybridIntegerationWeatherService.CallContext();
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Test.startTest();
        HybridIntegerationWeatherService.WeatherResult r = HybridIntegerationWeatherService.fetchForLocation(locId, ctx);
        Test.stopTest();

        Assert.areEqual(locId, r.locationId);
        Assert.areEqual(12.345, r.weather.current.temperature_2m);
        Assert.areEqual(200, ctx.statusCode);
        Assert.isNotNull(ctx.requestTime);
        Assert.isNotNull(ctx.responseTime);
        Assert.isNotNull(ctx.durationMs);
        Assert.isTrue(ctx.responseSummary.contains('temperature_2m=12.345'));

        String ep = HybridIntegerationTestSupport.lastRequest.getEndpoint();
        Assert.isTrue(ep.startsWith('callout:Hybrid_Integeration_Weather/v1/forecast?'), ep);
        Assert.isTrue(ep.contains('latitude=51.507400'), ep);
        Assert.isTrue(ep.contains('longitude=-0.127800'), ep);
        Assert.isTrue(ep.contains('current=temperature_2m%2Crelative_humidity_2m%2Cprecipitation%2Cwind_speed_10m'), ep);
        Assert.isTrue(ep.contains('timezone=auto'), ep);
        Assert.areEqual('GET', HybridIntegerationTestSupport.lastRequest.getMethod());
    }

    @IsTest
    static void coordinatesOverloadWorks() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okJson()));
        Test.startTest();
        HybridIntegerationWeatherService.WeatherResult r = HybridIntegerationWeatherService.fetchForCoordinates(48.8566, 2.3522);
        Test.stopTest();
        Assert.isNotNull(r.weather);
        Assert.isNull(r.locationId);
    }

    @IsTest
    static void invalidLatitudeRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        expect(91, 0, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        expect(-90.5, 0, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void invalidLongitudeRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        expect(0, 180.1, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        expect(0, -181, null, HybridIntegerationIntegrationException.INVALID_COORDINATES);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void nullCoordinatesRejected() {
        HybridIntegerationTestSupport.reset();
        expect(null, 0, null, HybridIntegerationIntegrationException.NULL_COORDINATES);
        expect(0, null, null, HybridIntegerationIntegrationException.NULL_COORDINATES);
        // via a stored record with empty coordinates
        try {
            HybridIntegerationWeatherService.fetchForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_NULL));
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.NULL_COORDINATES, e.errorCode);
        }
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void storedInvalidCoordinatesRejected() {
        try {
            HybridIntegerationWeatherService.fetchForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LAT));
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COORDINATES, e.errorCode);
        }
        try {
            HybridIntegerationWeatherService.fetchForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LON));
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COORDINATES, e.errorCode);
        }
    }

    @IsTest
    static void missingLocationRejected() {
        for (Id badId : new List<Id>{ HybridIntegerationTestSupport.missingLocationId(), null }) {
            try {
                HybridIntegerationWeatherService.fetchForLocation(badId);
                Assert.fail('Expected exception');
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, e.errorCode);
            }
        }
    }

    @IsTest static void http400() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(400, '{"error":true,"reason":"Latitude must be in range"}'), HybridIntegerationIntegrationException.HTTP_BAD_REQUEST);
    }
    @IsTest static void http401() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(401, '{}'), HybridIntegerationIntegrationException.HTTP_AUTH);
    }
    @IsTest static void http403() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(403, '{}'), HybridIntegerationIntegrationException.HTTP_AUTH);
    }
    @IsTest static void http429() {
        expect(10, 10, new HybridIntegerationTestSupport.Mock(429, '{"error":true,"reason":"Too many requests"}'), HybridIntegerationIntegrationException.HTTP_RATE_LIMIT);
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
    @IsTest static void missingCurrentData() {
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
            HybridIntegerationWeatherService.fetchForCoordinates(10, 10, ctx);
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

    private static void expect(Decimal lat, Decimal lon, HybridIntegerationTestSupport.Mock mock, String expectedCode) 
    {
        Boolean isCalloutTest = mock != null;
        if (isCalloutTest) {
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
        }
        Boolean thrown = false;
        try {
            HybridIntegerationWeatherService.fetchForCoordinates(lat, lon);
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
