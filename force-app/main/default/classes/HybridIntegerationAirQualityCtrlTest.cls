@IsTest
private class HybridIntegerationAirQualityCtrlTest {
    @TestSetup
    static void setup() {
        HybridIntegerationTestSupport.createLocations();
    }

    @IsTest
    static void fetchAndSaveCreatesReadingAndSuccessLog() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.airQualityJson('2026-07-01T14:30', 3600)));
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(locId);
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.saved);
        Assert.isNotNull(r.readingId);
        Assert.isNotNull(r.logId);
        Assert.areEqual(10.12, r.pm25);
        Assert.areEqual(20.46, r.pm10);
        Assert.areEqual(42, r.usAqi);
        Assert.areEqual(35, r.europeanAqi);
        Assert.areEqual(55.50, r.ozone);
        Assert.areEqual(18.00, r.nitrogenDioxide);

        Air_Quality_Reading__c row = [SELECT Location__c, Station__c, PM25__c, PM10__c, US_AQI__c, European_AQI__c, Ozone__c,
            Nitrogen_Dioxide__c, Recorded_At__c, Data_Source__c, Measurement_Type__c FROM Air_Quality_Reading__c WHERE Id = :r.readingId];
        Assert.areEqual(locId, row.Location__c);
        Assert.isNull(row.Station__c);
        Assert.areEqual(10.12, row.PM25__c);
        Assert.areEqual(20.46, row.PM10__c);
        Assert.areEqual(42, row.US_AQI__c);
        Assert.areEqual(35, row.European_AQI__c);
        Assert.areEqual(55.50, row.Ozone__c);
        Assert.areEqual(18.00, row.Nitrogen_Dioxide__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 1, 13, 30, 0), row.Recorded_At__c);
        Assert.areEqual('Open-Meteo', row.Data_Source__c);
        Assert.areEqual('Forecast', row.Measurement_Type__c);

        Integration_Log__c log = [SELECT Integeration_Name__c, HTTP_Method__c, Status__c, Status_Code__c, Endpoint__c,
            Request_Time__c, Response_Time__c, Duration_ms__c, Correlation_ID__c, Error_Message__c, Response_Summary__c
            FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Open-Meteo Air Quality', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.areEqual('Success', log.Status__c);
        Assert.areEqual(200, log.Status_Code__c);
        Assert.isTrue(log.Endpoint__c.startsWith('callout:Hybrid_Integeration_Air_Quality/v1/air-quality'));
        Assert.isNotNull(log.Request_Time__c);
        Assert.isNotNull(log.Response_Time__c);
        Assert.isNotNull(log.Duration_ms__c);
        Assert.areEqual(r.correlationId, log.Correlation_ID__c);
        Assert.isNull(log.Error_Message__c);
        Assert.isTrue(log.Response_Summary__c.contains('us_aqi=42'));
    }

    @IsTest
    static void getAirQualityDoesNotSaveButLogs() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, HybridIntegerationTestSupport.okAirQualityJson()));
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.getAirQualityForLocation(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isTrue(r.success);
        Assert.isFalse(r.saved);
        Assert.isNull(r.readingId);
        Assert.areEqual(42, r.usAqi);
        Assert.areEqual('Europe/London', r.timezone);
        Assert.areEqual(0, [SELECT COUNT() FROM Air_Quality_Reading__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Success' AND Integeration_Name__c = 'Open-Meteo Air Quality']);
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
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.TIMEOUT, r.errorCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Air_Quality_Reading__c]);
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Failed', log.Status__c);
        Assert.isNull(log.Status_Code__c);
        Assert.isTrue(log.Error_Message__c.startsWith('TIMEOUT'));
    }

    @IsTest
    static void missingLocationReturnsFailureWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.missingLocationId());
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, r.errorCode);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Failed' AND Integeration_Name__c = 'Open-Meteo Air Quality']);
    }

    @IsTest
    static void invalidAndNullCoordinatesReturnFailure() {
        HybridIntegerationTestSupport.reset();
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse a = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LAT));
        HybridIntegerationAirQualityController.AirQualityApiResponse b = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_BAD_LON));
        HybridIntegerationAirQualityController.AirQualityApiResponse c = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_NULL));
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
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.HTTP_SERVER_ERROR, r.errorCode);
        Assert.isNull(r.logId);
    }

    @IsTest
    static void userMessagesDoNotLeakInternalDetails() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(500, '{"reason":"secret-internal-detail"}'));
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.message.contains('secret-internal-detail'));
        Assert.isFalse(r.message.contains('Class.'), 'No stack trace text');
    }

    @IsTest
    static void getLatestReadingReturnsMostRecentSavedReading() {
        Id locId = HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID);
        insert new List<Air_Quality_Reading__c>{
            new Air_Quality_Reading__c(Location__c = locId, PM25__c = 1, US_AQI__c = 10, Recorded_At__c = Datetime.newInstanceGmt(2026, 11, 10, 10, 0, 0)),
            new Air_Quality_Reading__c(Location__c = locId, PM25__c = 7.5, US_AQI__c = 55, Recorded_At__c = Datetime.newInstanceGmt(2026, 11, 12, 10, 0, 0))
        };
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.getLatestReading(locId);
        Assert.isTrue(r.success);
        Assert.isTrue(r.found);
        Assert.areEqual(7.5, r.pm25);
        Assert.areEqual(55, r.usAqi);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 12, 10, 0, 0), r.recordedAt);
        Assert.isNull(r.logId, 'Reading a saved record is not an integration call');
    }

    @IsTest
    static void getLatestReadingWithNoDataAndBadLocation() {
        HybridIntegerationAirQualityController.AirQualityApiResponse none = HybridIntegerationAirQualityController.getLatestReading(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Assert.isTrue(none.success);
        Assert.isFalse(none.found);
        HybridIntegerationAirQualityController.AirQualityApiResponse missing = HybridIntegerationAirQualityController.getLatestReading(HybridIntegerationTestSupport.missingLocationId());
        Assert.isFalse(missing.success);
        Assert.areEqual(HybridIntegerationIntegrationException.LOCATION_NOT_FOUND, missing.errorCode);
    }

    private static void assertHttpFailure(Integer status, String body, String expectedCode) {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(status, body));
        Test.startTest();
        HybridIntegerationAirQualityController.AirQualityApiResponse r = HybridIntegerationAirQualityController.fetchAndSaveAirQuality(HybridIntegerationTestSupport.locationId(HybridIntegerationTestSupport.LOC_VALID));
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.isFalse(r.saved);
        Assert.areEqual(expectedCode, r.errorCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Air_Quality_Reading__c]);
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c, Integeration_Name__c, HTTP_Method__c
            FROM Integration_Log__c WHERE Id = :r.logId];
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual(status, log.Status_Code__c);
        Assert.areEqual('Open-Meteo Air Quality', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.isTrue(log.Error_Message__c.startsWith(expectedCode), log.Error_Message__c);
    }
}
