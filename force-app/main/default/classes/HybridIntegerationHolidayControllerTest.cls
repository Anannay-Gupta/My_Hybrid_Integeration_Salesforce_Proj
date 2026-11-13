@IsTest
private class HybridIntegerationHolidayControllerTest {
    private static final List<String> RELIGIOUS_TYPES =
        new List<String>{ 'CHRISTIAN_HOLIDAY', 'ORTHODOX_HOLIDAY', 'MUSLIM_HOLIDAY', 'JEWISH_HOLIDAY', 'HINDU_HOLIDAY' };

    private static HybridIntegerationTestSupport.RoutedMock mockWith(String apiType, List<String> items) {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.bodyByType.put(apiType, HybridIntegerationTestSupport.holidayArray(items));
        return m;
    }

    // ---- one successful retrieval per Salesforce category -----------------------------------------

    @IsTest static void publicHolidays() { assertCategorySaved('Public', 'PUBLIC_HOLIDAY'); }
    @IsTest static void bankHolidays() { assertCategorySaved('Bank', 'BANK_HOLIDAY'); }
    @IsTest static void stateHolidays() { assertCategorySaved('State', 'STATE_HOLIDAY'); }
    @IsTest static void localHolidays() { assertCategorySaved('Local', 'LOCAL_HOLIDAY'); }
    @IsTest static void provinceTerritoryHolidays() { assertCategorySaved('Province_Territory', 'PROVINCE_TERRITORY_HOLIDAY'); }
    @IsTest static void governmentHolidays() { assertCategorySaved('Government', 'GOVERNMENT_HOLIDAY'); }
    @IsTest static void privateHolidays() { assertCategorySaved('Private', 'PRIVATE_SECTOR_HOLIDAY'); }
    @IsTest static void observances() { assertCategorySaved('Observance', 'OBSERVANCE'); }
    @IsTest static void optionalHolidays() { assertCategorySaved('Optional', 'OPTIONAL_HOLIDAY'); }

    @IsTest
    static void publicHolidayFullFlowRecordsLogAndMetrics() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, mockWith('PUBLIC_HOLIDAY', new List<String>{
            HybridIntegerationTestSupport.holidayItem('GB', '2026-12-25', 'Christmas Day', 'PUBLIC_HOLIDAY'),
            HybridIntegerationTestSupport.holidayItem('GB', '2026-12-26', 'Boxing Day', 'PUBLIC_HOLIDAY') }));
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('gb', 'Public');
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.areEqual('GB', r.countryCode);
        Assert.areEqual('Public', r.holidayType);
        Assert.areEqual(1, r.requestCount);
        Assert.areEqual(2, r.retrievedCount);
        Assert.areEqual(2, r.savedCount);
        Assert.areEqual(2, r.insertedCount);
        Assert.areEqual(0, r.failedCount);
        Assert.areEqual(0, r.monthlyRequestsUsedBefore);
        Assert.areEqual(2700, r.monthlyRequestThreshold);
        Assert.areEqual(1, r.logIds.size());

        Integration_Log__c log = [SELECT Integeration_Name__c, HTTP_Method__c, Status__c, Status_Code__c, Endpoint__c, Request_Time__c,
            Response_Time__c, Duration_ms__c, Correlation_ID__c, Error_Message__c, Response_Summary__c
            FROM Integration_Log__c WHERE Id = :r.logIds[0]];
        Assert.areEqual('API Ninjas Holidays', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.areEqual('Success', log.Status__c);
        Assert.areEqual(200, log.Status_Code__c);
        Assert.areEqual('callout:Hybrid_Integration_Holidays/v2/holidays?country=GB&type=PUBLIC_HOLIDAY', log.Endpoint__c);
        Assert.isNotNull(log.Request_Time__c);
        Assert.isNotNull(log.Response_Time__c);
        Assert.isNotNull(log.Duration_ms__c);
        Assert.areEqual(r.correlationId, log.Correlation_ID__c);
        Assert.isNull(log.Error_Message__c);
        Assert.isTrue(log.Response_Summary__c.contains('returned=2'));
    }

    @IsTest
    static void religiousUsesFiveRequestsAndMapsEverythingToReligious() {
        HybridIntegerationTestSupport.reset();
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        for (String t : RELIGIOUS_TYPES) {
            m.bodyByType.put(t, HybridIntegerationTestSupport.holidayArray(new List<String>{
                HybridIntegerationTestSupport.holidayItem('IN', '2026-11-08', 'Festival ' + t, t) }));
        }
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('IN', 'Religious');
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.areEqual(5, r.requestCount);
        Assert.areEqual(5, r.retrievedCount);
        Assert.areEqual(5, r.savedCount);
        Assert.areEqual(5, r.logIds.size());
        Assert.areEqual(5, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(5, [SELECT COUNT() FROM Public_Holiday__c WHERE Holiday_Type__c = 'Religious']);
        for (String t : RELIGIOUS_TYPES) {
            String idPattern = '%|' + t + '|%';
            Assert.areEqual(1, [SELECT COUNT() FROM Public_Holiday__c WHERE External_Holiday_ID__c LIKE :idPattern], t);
        }
        // one log per attempted request, all sharing the search's correlation ID
        List<Integration_Log__c> logs = [SELECT Status__c, Correlation_ID__c, Endpoint__c FROM Integration_Log__c];
        Assert.areEqual(5, logs.size());
        for (Integration_Log__c l : logs) {
            Assert.areEqual('Success', l.Status__c);
            Assert.areEqual(r.correlationId, l.Correlation_ID__c);
        }
    }

    @IsTest
    static void nationalHolidaysWithReligiousOriginStayPublic() {
        Test.setMock(HttpCalloutMock.class, mockWith('PUBLIC_HOLIDAY', new List<String>{
            HybridIntegerationTestSupport.holidayItem('DE', '2026-04-03', 'Good Friday', 'PUBLIC_HOLIDAY') }));
        Test.startTest();
        HybridIntegerationHolidayController.fetchAndSaveHolidays('DE', 'Public');
        Test.stopTest();
        Assert.areEqual('Public', [SELECT Holiday_Type__c FROM Public_Holiday__c].Holiday_Type__c);
    }

    @IsTest
    static void invalidEntriesAreSkippedWithWarningsAndValidOnesSaved() {
        Test.setMock(HttpCalloutMock.class, mockWith('PUBLIC_HOLIDAY', new List<String>{
            HybridIntegerationTestSupport.holidayItem('US', '2026-07-04', 'Independence Day', 'PUBLIC_HOLIDAY'),
            '{"country":"United States","iso":"US","year":2026,"date":"2026-13-45","day":"x","name":"Bad Date","type":"PUBLIC_HOLIDAY"}',
            '{"iso":"US","date":"2026-01-01","type":"PUBLIC_HOLIDAY"}',
            HybridIntegerationTestSupport.holidayItem('US', '2026-01-01', 'Wrong Type', 'FLAG_DAY') }));
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isTrue(r.success, r.message);
        Assert.areEqual(4, r.retrievedCount);
        Assert.areEqual(1, r.mappedCount);
        Assert.areEqual(3, r.skippedCount);
        Assert.areEqual(3, r.warnings.size());
        Assert.areEqual(1, r.savedCount);
    }

    @IsTest
    static void emptyApiResponseIsSuccessWithNothingSaved() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.RoutedMock());
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Local');
        Test.stopTest();
        Assert.isTrue(r.success);
        Assert.areEqual(1, r.requestCount);
        Assert.areEqual(0, r.retrievedCount);
        Assert.areEqual(0, r.savedCount);
        Assert.areEqual(1, r.logIds.size(), 'The attempted request is still logged');
    }

    // ---- failures ------------------------------------------------------------------------------------

    @IsTest static void http400() { assertHttpFailure(400, '{"error":"Invalid country"}', HybridIntegerationIntegrationException.HTTP_BAD_REQUEST); }
    @IsTest static void http401() { assertHttpFailure(401, '{"error":"Invalid API Key"}', HybridIntegerationIntegrationException.HTTP_AUTH); }
    @IsTest static void http403() { assertHttpFailure(403, '{"error":"forbidden"}', HybridIntegerationIntegrationException.HTTP_AUTH); }
    @IsTest static void http429() { assertHttpFailure(429, '{"error":"quota"}', HybridIntegerationIntegrationException.HTTP_RATE_LIMIT); }
    @IsTest static void http500() { assertHttpFailure(500, 'boom', HybridIntegerationIntegrationException.HTTP_SERVER_ERROR); }
    @IsTest static void malformedJson() { assertHttpFailure(200, '[{"name":', HybridIntegerationIntegrationException.MALFORMED_JSON); }
    @IsTest static void emptyBody() { assertHttpFailure(200, '', HybridIntegerationIntegrationException.EMPTY_RESPONSE); }

    @IsTest
    static void timeoutIsReportedAndLoggedWithoutStatusCode() {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.exceptionMessage = 'Read timed out';
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.TIMEOUT, r.errorCode);
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c FROM Integration_Log__c WHERE Id = :r.logIds[0]];
        Assert.areEqual('Failed', log.Status__c);
        Assert.isNull(log.Status_Code__c);
        Assert.isTrue(log.Error_Message__c.startsWith('TIMEOUT'));
    }

    @IsTest
    static void religiousFailureMidwayLogsOnlyAttemptedRequestsAndSavesNothing() {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        for (String t : RELIGIOUS_TYPES) {
            m.bodyByType.put(t, HybridIntegerationTestSupport.holidayArray(new List<String>{ HybridIntegerationTestSupport.holidayItem('US', '2026-05-05', 'D ' + t, t) }));
        }
        m.statusByType.put('ORTHODOX_HOLIDAY', 500);   // second request fails
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Religious');
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(2, r.requestCount);
        Assert.areEqual(0, [SELECT COUNT() FROM Public_Holiday__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Success']);
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void invalidInputsAreRejectedWithoutCalloutOrLog() {
        HybridIntegerationTestSupport.reset();
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse noCountry = HybridIntegerationHolidayController.fetchAndSaveHolidays('', 'Public');
        HybridIntegerationHolidayController.HolidayApiResponse badCountry = HybridIntegerationHolidayController.fetchAndSaveHolidays('USA', 'Public');
        HybridIntegerationHolidayController.HolidayApiResponse noCategory = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', null);
        HybridIntegerationHolidayController.HolidayApiResponse badCategory = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Federal');
        Test.stopTest();
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COUNTRY, noCountry.errorCode);
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COUNTRY, badCountry.errorCode);
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_CATEGORY, noCategory.errorCode);
        Assert.areEqual(HybridIntegerationIntegrationException.INVALID_CATEGORY, badCategory.errorCode);
        for (HybridIntegerationHolidayController.HolidayApiResponse r : new List<HybridIntegerationHolidayController.HolidayApiResponse>{ noCountry, badCountry, noCategory, badCategory }) {
            Assert.isFalse(r.success);
            Assert.areEqual(0, r.requestCount);
            Assert.isNotNull(r.message);
        }
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c], 'Rejected input must not inflate the quota counter');
    }

    @IsTest
    static void quotaReachedRejectsBeforeAnyCalloutAndDoesNotLog() {
        HybridIntegerationHolidayService.safetyThreshold = 3;
        List<Integration_Log__c> existing = new List<Integration_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            existing.add(new Integration_Log__c(Integeration_Name__c = 'API Ninjas Holidays', HTTP_Method__c = 'GET',
                Status__c = 'Success', Request_Time__c = Datetime.now()));
        }
        insert existing;
        HybridIntegerationTestSupport.reset();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.QUOTA_EXCEEDED, r.errorCode);
        Assert.areEqual(0, r.requestCount);
        Assert.areEqual(3, r.monthlyRequestsUsedBefore);
        Assert.areEqual(3, r.monthlyRequestThreshold);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(3, [SELECT COUNT() FROM Integration_Log__c]);
    }

    @IsTest
    static void insufficientQuotaForReligiousFiveRequestsRejectsWholeSearch() {
        HybridIntegerationHolidayService.safetyThreshold = 7;
        List<Integration_Log__c> existing = new List<Integration_Log__c>();
        for (Integer i = 0; i < 3; i++) {
            existing.add(new Integration_Log__c(Integeration_Name__c = 'API Ninjas Holidays', HTTP_Method__c = 'GET',
                Status__c = 'Success', Request_Time__c = Datetime.now()));
        }
        insert existing;   // 3 + 5 = 8 > 7
        HybridIntegerationTestSupport.reset();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Religious');
        Assert.areEqual(HybridIntegerationIntegrationException.QUOTA_EXCEEDED, r.errorCode);
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(0, [SELECT COUNT() FROM Public_Holiday__c]);
    }

    @IsTest
    static void loggerFailureDoesNotHideSuccessOrFailure() {
        HybridIntegerationIntegrationLogger.forceFailure = true;
        Test.setMock(HttpCalloutMock.class, mockWith('PUBLIC_HOLIDAY', new List<String>{
            HybridIntegerationTestSupport.holidayItem('US', '2026-07-04', 'Independence Day', 'PUBLIC_HOLIDAY') }));
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse ok = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isTrue(ok.success, 'Holiday was saved even though the log could not be written');
        Assert.areEqual(1, ok.savedCount);
        Assert.areEqual(0, ok.logIds.size());
        Assert.isNotNull(HybridIntegerationIntegrationLogger.lastLoggingError);
    }

    @IsTest
    static void loggerFailureDoesNotHideHttpError() {
        HybridIntegerationIntegrationLogger.forceFailure = true;
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.statusByType.put('PUBLIC_HOLIDAY', 500);
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(HybridIntegerationIntegrationException.HTTP_SERVER_ERROR, r.errorCode);
        Assert.areEqual(0, r.logIds.size());
    }

    @IsTest
    static void userMessagesDoNotLeakInternalDetails() {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.statusByType.put('PUBLIC_HOLIDAY', 500);
        m.bodyByType.put('PUBLIC_HOLIDAY', '{"error":"secret-internal-detail"}');
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isFalse(r.message.contains('secret-internal-detail'));
        Assert.isFalse(r.message.contains('Class.'));
    }

    // ---- helpers ------------------------------------------------------------------------------------

    private static void assertCategorySaved(String salesforceCategory, String apiType) {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, mockWith(apiType, new List<String>{
            HybridIntegerationTestSupport.holidayItem('US', '2026-03-01', 'Sample Day', apiType) }));
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', salesforceCategory);
        Test.stopTest();

        Assert.isTrue(r.success, r.message);
        Assert.areEqual(1, r.requestCount);
        Assert.areEqual(1, r.retrievedCount);
        Assert.areEqual(1, r.savedCount);
        Assert.areEqual('callout:Hybrid_Integration_Holidays/v2/holidays?country=US&type=' + apiType, HybridIntegerationTestSupport.requestedEndpoints[0]);
        Assert.isFalse(HybridIntegerationTestSupport.requestedEndpoints[0].containsIgnoreCase('year'));

        Public_Holiday__c h = [SELECT Name, Holiday_Date__c, Country_Code__c, Holiday_Type__c, Location__c, Is_Global__c, External_Holiday_ID__c
            FROM Public_Holiday__c];
        Assert.areEqual('Sample Day', h.Name);
        Assert.areEqual(Date.newInstance(2026, 3, 1), h.Holiday_Date__c);
        Assert.areEqual('US', h.Country_Code__c);
        Assert.areEqual(salesforceCategory, h.Holiday_Type__c);
        Assert.isNull(h.Location__c);
        Assert.areEqual(false, h.Is_Global__c);
        Assert.areEqual('US|2026-03-01|' + apiType + '|sample day', h.External_Holiday_ID__c);
    }

    private static void assertHttpFailure(Integer status, String body, String expectedCode) {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.statusByType.put('PUBLIC_HOLIDAY', status);
        m.bodyByType.put('PUBLIC_HOLIDAY', body);
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        HybridIntegerationHolidayController.HolidayApiResponse r = HybridIntegerationHolidayController.fetchAndSaveHolidays('US', 'Public');
        Test.stopTest();
        Assert.isFalse(r.success);
        Assert.areEqual(expectedCode, r.errorCode);
        Assert.areEqual(1, r.requestCount, 'A failed request still counts as attempted');
        Assert.areEqual(0, r.savedCount);
        Assert.areEqual(0, [SELECT COUNT() FROM Public_Holiday__c]);
        Assert.areEqual(1, r.logIds.size());
        Integration_Log__c log = [SELECT Status__c, Status_Code__c, Error_Message__c, Integeration_Name__c, HTTP_Method__c
            FROM Integration_Log__c WHERE Id = :r.logIds[0]];
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual(status, log.Status_Code__c);
        Assert.areEqual('API Ninjas Holidays', log.Integeration_Name__c);
        Assert.areEqual('GET', log.HTTP_Method__c);
        Assert.isTrue(log.Error_Message__c.startsWith(expectedCode), log.Error_Message__c);
    }
}
