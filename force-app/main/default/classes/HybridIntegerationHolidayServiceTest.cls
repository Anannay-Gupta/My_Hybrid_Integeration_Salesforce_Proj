@IsTest
private class HybridIntegerationHolidayServiceTest {

    private static HybridIntegerationTestSupport.RoutedMock mockFor(String apiType, String dateText, String name) {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.bodyByType.put(apiType, HybridIntegerationTestSupport.holidayArray(new List<String>{
            HybridIntegerationTestSupport.holidayItem('US', dateText, name, apiType) }));
        return m;
    }

    private static void insertHolidayLogs(Integer count, Datetime requestTime, String integrationName) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integer i = 0; i < count; i++) {
            logs.add(new Integration_Log__c(Integeration_Name__c = integrationName, HTTP_Method__c = 'GET',
                Status__c = 'Success', Request_Time__c = requestTime));
        }
        insert logs;
    }

    private static Datetime lastMonth() {
        Datetime now = Datetime.now();
        return Datetime.newInstanceGmt(now.yearGmt(), now.monthGmt(), 1).addSeconds(-60);
    }

    @IsTest
    static void everyNonReligiousCategoryMakesExactlyOneCorrectRequest() {
        Map<String, String> expected = new Map<String, String>{
            'Public' => 'PUBLIC_HOLIDAY', 'Bank' => 'BANK_HOLIDAY', 'State' => 'STATE_HOLIDAY', 'Local' => 'LOCAL_HOLIDAY',
            'Province_Territory' => 'PROVINCE_TERRITORY_HOLIDAY', 'Government' => 'GOVERNMENT_HOLIDAY',
            'Private' => 'PRIVATE_SECTOR_HOLIDAY', 'Observance' => 'OBSERVANCE', 'Optional' => 'OPTIONAL_HOLIDAY'
        };
        Test.startTest();
        for (String sf : expected.keySet()) {
            HybridIntegerationTestSupport.reset();
            Test.setMock(HttpCalloutMock.class, mockFor(expected.get(sf), '2026-03-01', 'Sample'));
            HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
            HybridIntegerationHolidayService.fetchHolidays('US', sf, 'corr-1', fr);
            Assert.areEqual(1, HybridIntegerationTestSupport.callCount, sf);
            Assert.areEqual('callout:Hybrid_Integration_Holidays/v2/holidays?country=US&type=' + expected.get(sf),
                HybridIntegerationTestSupport.requestedEndpoints[0], sf);
            Assert.areEqual(1, fr.requests.size());
            Assert.isTrue(fr.requests[0].success);
            Assert.areEqual(1, fr.holidays.size(), sf);
        }
        Test.stopTest();
    }

    @IsTest
    static void religiousMakesFiveSeparateRequestsAndCombinesResults() {
        HybridIntegerationTestSupport.reset();
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        for (String t : new List<String>{ 'CHRISTIAN_HOLIDAY', 'ORTHODOX_HOLIDAY', 'MUSLIM_HOLIDAY', 'JEWISH_HOLIDAY', 'HINDU_HOLIDAY' }) {
            m.bodyByType.put(t, HybridIntegerationTestSupport.holidayArray(new List<String>{
                HybridIntegerationTestSupport.holidayItem('IN', '2026-05-05', t + ' day', t) }));
        }
        Test.setMock(HttpCalloutMock.class, m);
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        Test.startTest();
        HybridIntegerationHolidayService.fetchHolidays('IN', 'Religious', 'corr-2', fr);
        Test.stopTest();
        Assert.areEqual(5, HybridIntegerationTestSupport.callCount);
        Assert.areEqual(5, fr.requests.size());
        Assert.areEqual(5, fr.holidays.size());
        Set<String> typesRequested = new Set<String>();
        for (String ep : HybridIntegerationTestSupport.requestedEndpoints) {
            Assert.isTrue(ep.startsWith('callout:Hybrid_Integration_Holidays/v2/holidays?country=IN&type='), ep);
            typesRequested.add(ep.substringAfter('type='));
        }
        Assert.areEqual(5, typesRequested.size());
        for (HybridIntegerationHolidayService.RequestRecord rec : fr.requests) {
            Assert.areEqual('corr-2', rec.context.correlationId);
            Assert.areEqual(1, rec.returnedCount);
        }
    }

    @IsTest
    static void yearParameterIsNeverSentAndNoApiKeyHeaderIsSetByApex() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.RoutedMock());
        Test.startTest();
        HybridIntegerationHolidayService.fetchHolidays('DE', 'Religious', 'c', new HybridIntegerationHolidayService.FetchResult());
        HybridIntegerationHolidayService.fetchHolidays('DE', 'Public', 'c', new HybridIntegerationHolidayService.FetchResult());
        Test.stopTest();
        Assert.areEqual(6, HybridIntegerationTestSupport.requestedEndpoints.size());
        for (String ep : HybridIntegerationTestSupport.requestedEndpoints) {
            Assert.isFalse(ep.containsIgnoreCase('year'), ep);
        }
        Assert.isTrue(String.isBlank(HybridIntegerationTestSupport.lastRequest.getHeader('X-Api-Key')), 'Key is injected by the credential, never by Apex');
        Assert.areEqual('GET', HybridIntegerationTestSupport.lastRequest.getMethod());
    }

    @IsTest
    static void countryCodeIsDynamicAndUppercased() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.RoutedMock());
        Test.startTest();
        for (String code : new List<String>{ 'us', 'GB', ' fr ', 'Jp' }) {
            HybridIntegerationTestSupport.reset();
            HybridIntegerationHolidayService.fetchHolidays(code, 'Bank', 'c', new HybridIntegerationHolidayService.FetchResult());
            Assert.areEqual('callout:Hybrid_Integration_Holidays/v2/holidays?country=' + code.trim().toUpperCase() + '&type=BANK_HOLIDAY',
                HybridIntegerationTestSupport.requestedEndpoints[0]);
        }
        Test.stopTest();
    }

    @IsTest
    static void invalidCountryRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        for (String bad : new List<String>{ null, '', '  ', 'U', 'USA', '1A', 'U S' }) {
            try {
                HybridIntegerationHolidayService.fetchHolidays(bad, 'Public', 'c', new HybridIntegerationHolidayService.FetchResult());
                Assert.fail('Expected rejection of ' + bad);
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.INVALID_COUNTRY, e.errorCode);
            }
        }
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void invalidCategoryRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        for (String bad : new List<String>{ null, '', 'Federal', 'PUBLIC_HOLIDAY' }) {
            try {
                HybridIntegerationHolidayService.fetchHolidays('US', bad, 'c', new HybridIntegerationHolidayService.FetchResult());
                Assert.fail('Expected rejection of ' + bad);
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.INVALID_CATEGORY, e.errorCode);
            }
        }
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void emptyArrayIsASuccessfulRequestWithNoHolidays() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.RoutedMock());
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        Test.startTest();
        HybridIntegerationHolidayService.fetchHolidays('US', 'Local', 'c', fr);
        Test.stopTest();
        Assert.areEqual(1, fr.requests.size());
        Assert.isTrue(fr.requests[0].success);
        Assert.areEqual(0, fr.holidays.size());
    }

    // ---- HTTP / payload failures ------------------------------------------------------------------

    @IsTest static void http400() { assertFailure(400, '{"error":"Invalid country"}', HybridIntegerationIntegrationException.HTTP_BAD_REQUEST); }
    @IsTest static void http401() { assertFailure(401, '{"error":"Invalid API Key"}', HybridIntegerationIntegrationException.HTTP_AUTH); }
    @IsTest static void http403() { assertFailure(403, '{"error":"forbidden"}', HybridIntegerationIntegrationException.HTTP_AUTH); }
    @IsTest static void http429() { assertFailure(429, '{"error":"quota"}', HybridIntegerationIntegrationException.HTTP_RATE_LIMIT); }
    @IsTest static void http500() { assertFailure(500, 'oops', HybridIntegerationIntegrationException.HTTP_SERVER_ERROR); }
    @IsTest static void unexpectedStatus() { assertFailure(302, '', HybridIntegerationIntegrationException.HTTP_UNEXPECTED); }
    @IsTest static void emptyBody() { assertFailure(200, '', HybridIntegerationIntegrationException.EMPTY_RESPONSE); }
    @IsTest static void malformedJson() { assertFailure(200, '[{"name":', HybridIntegerationIntegrationException.MALFORMED_JSON); }
    @IsTest static void objectInsteadOfArray() { assertFailure(200, '{"error":"x"}', HybridIntegerationIntegrationException.MALFORMED_JSON); }

    @IsTest
    static void calloutExceptionAndTimeoutAreTranslated() {
        Test.startTest();
        for (String msg : new List<String>{ 'Read timed out', 'Connection refused' }) {
            HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
            m.exceptionMessage = msg;
            Test.setMock(HttpCalloutMock.class, m);
            HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
            try {
                HybridIntegerationHolidayService.fetchHolidays('US', 'Public', 'c', fr);
                Assert.fail('Expected exception');
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(msg == 'Read timed out' ? HybridIntegerationIntegrationException.TIMEOUT : HybridIntegerationIntegrationException.CALLOUT_FAILED, e.errorCode);
            }
            Assert.areEqual(1, fr.requests.size());
            Assert.isFalse(fr.requests[0].success);
            Assert.isNotNull(fr.requests[0].errorMessage);
        }
        Test.stopTest();
    }

    @IsTest
    static void religiousFailsFastAndKeepsAttemptedRequestsForLogging() {
        HybridIntegerationTestSupport.reset();
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.statusByType.put('MUSLIM_HOLIDAY', 429);   // third request in order
        Test.setMock(HttpCalloutMock.class, m);
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        Test.startTest();
        try {
            HybridIntegerationHolidayService.fetchHolidays('US', 'Religious', 'c', fr);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.HTTP_RATE_LIMIT, e.errorCode);
        }
        Test.stopTest();
        Assert.areEqual(3, HybridIntegerationTestSupport.callCount, 'Remaining requests are not attempted');
        Assert.areEqual(3, fr.requests.size());
        Assert.isTrue(fr.requests[0].success);
        Assert.isTrue(fr.requests[1].success);
        Assert.isFalse(fr.requests[2].success);
        Assert.areEqual(429, fr.requests[2].context.statusCode);
        Assert.isTrue(fr.requests[2].context.responseSummary != null);
        Assert.isNotNull(fr.requests[2].context.durationMs);
    }

    // ---- quota --------------------------------------------------------------------------------------

    @IsTest
    static void defaultThresholdIs2700OfA3000Plan() {
        Assert.areEqual(2700, HybridIntegerationHolidayService.DEFAULT_SAFETY_THRESHOLD);
        Assert.areEqual(3000, HybridIntegerationHolidayService.MONTHLY_REQUEST_LIMIT);
    }

    @IsTest
    static void quotaCountsOnlyThisMonthsApiNinjasLogs() {
        insertHolidayLogs(3, Datetime.now(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);
        insertHolidayLogs(2, Datetime.now(), HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER);          // other integration
        insertHolidayLogs(4, lastMonth(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);            // previous month
        Assert.areEqual(3, HybridIntegerationHolidayService.countRequestsThisMonth());
    }

    @IsTest
    static void successfulRequestBelowThresholdIsAllowed() {
        HybridIntegerationHolidayService.safetyThreshold = 5;
        insertHolidayLogs(3, Datetime.now(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);          // 3 + 1 <= 5
        Test.setMock(HttpCalloutMock.class, mockFor('PUBLIC_HOLIDAY', '2026-03-01', 'Sample'));
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        Test.startTest();
        HybridIntegerationHolidayService.fetchHolidays('US', 'Public', 'c', fr);
        Test.stopTest();
        Assert.areEqual(1, fr.requests.size());
        Assert.areEqual(3, fr.monthlyRequestsUsedBefore);
        Assert.areEqual(5, fr.safetyThreshold);
    }

    @IsTest
    static void requestThatExactlyReachesThresholdIsAllowedButNextIsRejected() {
        HybridIntegerationHolidayService.safetyThreshold = 5;
        insertHolidayLogs(4, Datetime.now(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);          // 4 + 1 = 5 -> ok
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.RoutedMock());
        Test.startTest();
        HybridIntegerationHolidayService.fetchHolidays('US', 'Public', 'c', new HybridIntegerationHolidayService.FetchResult());
        Test.stopTest();
        // simulate that request being logged: 5 used -> 5 + 1 > 5 -> rejected before any callout
        insertHolidayLogs(1, Datetime.now(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);
        HybridIntegerationTestSupport.reset();
        assertQuotaRejected('Public');
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void religiousNeedsFiveAvailableRequestsBeforeStarting() {
        HybridIntegerationHolidayService.safetyThreshold = 10;
        insertHolidayLogs(6, Datetime.now(), HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS);          // 6 + 5 = 11 > 10
        HybridIntegerationTestSupport.reset();
        assertQuotaRejected('Religious');
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount, 'No partial run of the five requests');
        // a single-request category would still fit (6 + 1 <= 10)
        HybridIntegerationHolidayService.assertQuotaAvailable(6, 1);
        // exactly five available is accepted
        HybridIntegerationHolidayService.assertQuotaAvailable(5, 5);
    }

    private static void assertQuotaRejected(String category) {
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        try {
            HybridIntegerationHolidayService.fetchHolidays('US', category, 'c', fr);
            Assert.fail('Expected quota rejection');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.QUOTA_EXCEEDED, e.errorCode);
        }
        Assert.areEqual(0, fr.requests.size());
    }

    private static void assertFailure(Integer status, String body, String expectedCode) {
        HybridIntegerationTestSupport.RoutedMock m = new HybridIntegerationTestSupport.RoutedMock();
        m.statusByType.put('PUBLIC_HOLIDAY', status);
        m.bodyByType.put('PUBLIC_HOLIDAY', body);
        Test.setMock(HttpCalloutMock.class, m);
        HybridIntegerationHolidayService.FetchResult fr = new HybridIntegerationHolidayService.FetchResult();
        Test.startTest();
        try {
            HybridIntegerationHolidayService.fetchHolidays('US', 'Public', 'c', fr);
            Assert.fail('Expected ' + expectedCode);
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(expectedCode, e.errorCode, e.getMessage());
            Assert.isNotNull(e.getSafeMessage());
        }
        Test.stopTest();
        Assert.areEqual(1, fr.requests.size());
        Assert.isFalse(fr.requests[0].success);
        Assert.isTrue(fr.requests[0].errorMessage.startsWith(expectedCode));
    }
}
