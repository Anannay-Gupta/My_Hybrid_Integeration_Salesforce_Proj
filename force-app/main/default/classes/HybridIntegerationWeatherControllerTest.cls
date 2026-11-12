@IsTest
private class HybridIntegerationWeatherControllerTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void fetchAndSaveCreatesSnapshotAndSuccessLog() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.weatherJson('2026-07-01T14:30', 3600)));
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(locId);
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.saved);
        Assert.isNotNull(r.snapshotId);
        Assert.isNotNull(r.logId);
        Assert.isNotNull(r.correlationId);

        Weather_Snapshot__c s = [SELECT Location__c, Temperature__c, Humidity__c, Wind_Speed__c, Precipitation__c,
            Recorded_At__c, Forecast_Type__c, Data_Source__c FROM Weather_Snapshot__c WHERE Id = :r.snapshotId];
        Assert.areEqual(locId, s.Location__c);
        Assert.areEqual(12.35, s.Temperature__c);
        Assert.areEqual(81.00, s.Humidity__c);
        Assert.areEqual(14.70, s.Wind_Speed__c);
        Assert.areEqual(0.00, s.Precipitation__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 1, 13, 30, 0), s.Recorded_At__c);
        Assert.areEqual('Current', s.Forecast_Type__c);
        Assert.areEqual('Open-Meteo', s.Data_Source__c);

        Integration_Log__c log = [SELECT Integeration_Name__c, HTTP_Method__c, Status__c, Status_Code__c, Endpoint__c,
            Request_Time__c, Response_Time__c, Duration_ms__c, Correlation_ID__c, Error_Message__c, Retry_Count__c
            FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Open-Meteo Weather', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.areEqual('Success', log.Status__c);
        Assert.areEqual(200, log.Status_Code__c);
        Assert.isTrue(log.Endpoint__c.startsWith('callout:Hybrid_Integeration_Weather/v1/forecast'));
        Assert.isNotNull(log.Request_Time__c);
        Assert.isNotNull(log.Response_Time__c);
        Assert.isNotNull(log.Duration_ms__c);
        Assert.areEqual(r.correlationId, log.Correlation_ID__c);
        Assert.isNull(log.Error_Message__c);
        Assert.areEqual(0, log.Retry_Count__c);
    }

    @IsTest
    static void getWeatherDoesNotSaveSnapshotButLogs() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okJson()));
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.getWeatherForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isTrue(r.success);
        Assert.isFalse(r.saved);
        Assert.isNull(r.snapshotId);
        Assert.areEqual(12.345, r.temperature);
        Assert.areEqual(81, r.humidity);
        Assert.areEqual(14.7, r.windSpeed);
        Assert.areEqual('Europe/London', r.timezone);
        Assert.areEqual(0, [SELECT COUNT() FROM Weather_Snapshot__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Success']);
    }

    @IsTest static void http429ReturnsFailureAndFailedLog() {
        assertHttpFailure(429, '{"reason":"Too many requests"}', HybridIntegerationIntegrationException.HTTP_RATE_LIMIT);
    }
    @IsTest static void http400ReturnsFailureAndFailedLog() {
        assertHttpFailure(400, '{"reason":"bad"}', HybridIntegerationIntegrationException.HTTP_BAD_REQUEST);
    }
    @IsTest static void http401ReturnsFailureAndFailedLog() {
        assertHttpFailure(401, '', HybridIntegerationIntegrationException.HTTP_AUTH);
    }
    @IsTest static void http500ReturnsFailureAndFailedLog() {
        assertHttpFailure(500, 'boom', HybridIntegerationIntegrationException.HTTP_SERVER_ERROR);
    }
    @IsTest static void malformedJsonReturnsFailureAndFailedLog() {
        assertHttpFailure(200, '{"current":', HybridIntegerationIntegrationException.MALFORMED_JSON);
    }
    @IsTest static void emptyBodyReturnsFailureAndFailedLog() {
        assertHttpFailure(200, '', HybridIntegerationIntegrationException.EMPTY_RESPONSE);
    }

    @IsTest
    static void timeoutReturnsFailureAndFailedLog() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock('Read timed out'));
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.TIMEOUT, r.errorCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Weather_Snapshot__c]);
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Failed', log.Status__c);
        Assert.isNull(log.Status_Code__c);
        Assert.isTrue(log.Error_Message__c.startsWith('TIMEOUT'));
    }

    @IsTest
    static void missingLocationReturnsFailureWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.missingLocationId());
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, r.errorCode);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void invalidAndNullCoordinatesReturnFailure() {
        HybridIntegerationTestSupport.reset();
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse a = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LAT));
        HybridIntegerationWeatherController.WeatherApiResponse b = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LON));
        HybridIntegerationWeatherController.WeatherApiResponse c = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_NULL));
        Test.stopTest();
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COORDINATES, a.errorCode);
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COORDINATES, b.errorCode);
        Assert.areEqual(HybridIntegerationIntegrationException.NULL_COORDINATES, c.errorCode);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(3, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void loggingFailureDoesNotHideOriginalFailure() {
        HybridIntegerationIntegrationLogger.forceFailure = true;
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(500, 'boom'));
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.HTTP_SERVER_ERROR, r.errorCode);
        Assert.isNull(r.logId);
    }

    @IsTest
    static void userMessagesDoNotLeakInternalDetails() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(500, '{"reason":"secret-internal-detail"}'));
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.message.contains('secret-internal-detail'));
        Assert.isFalse(r.message.contains('Class.'), 'No stack trace text');
    }

    private static void assertHttpFailure(Integer status, String body, String expectedCode) {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(status, body));
        Test.startTest();
        HybridIntegerationWeatherController.WeatherApiResponse r = HybridIntegerationWeatherController.fetchAndSaveWeather(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.isFalse(r.saved);
        Assert.areEqual(expectedCode, r.errorCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Weather_Snapshot__c]);
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c, Integeration_Name__c, HTTP_Method__c
            FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual(status, log.Status_Code__c);
        Assert.areEqual('Open-Meteo Weather', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.isTrue(log.Error_Message__c.startsWith(expectedCode), log.Error_Message__c);
    }
}
