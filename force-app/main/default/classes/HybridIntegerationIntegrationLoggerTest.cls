@IsTest
private class HybridIntegerationIntegrationLoggerTest {
    @IsTest
    static void logsSuccess() {
        HybridIntegerationIntegrationLogger.LogEntry e = new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER);
        e.success = true;
        e.endpoint = 'callout:X/v1/forecast?latitude=1';
        e.statusCode = 200;
        e.requestTime = Datetime.now().addSeconds(-1);
        e.responseTime = Datetime.now();
        e.durationMs = 123;
        e.correlationId = 'corr-1';
        e.responseSummary = 'ok';
        Id logId = HybridIntegerationIntegrationLogger.log(e);
        Assert.isNotNull(logId);
        Integration_Log__c row = [SELECT Integeration_Name__c, HTTP_Method__c, Status__c, Status_Code__c, Duration_ms__c,
            Correlation_ID__c, Retry_Count__c, Error_Message__c FROM Integration_Log__c WHERE Id = :logId];
        Assert.areEqual('Open-Meteo Weather', row.Integeration_Name__c);
        Assert.areEqual('GET', row.HTTP_Method__c);
        Assert.areEqual('Success', row.Status__c);
        Assert.areEqual(200, row.Status_Code__c);
        Assert.areEqual(123, row.Duration_ms__c);
        Assert.areEqual('corr-1', row.Correlation_ID__c);
        Assert.areEqual(0, row.Retry_Count__c);
        Assert.isNull(row.Error_Message__c);
    }

    @IsTest
    static void logsFailureAndTruncatesLongValues() {
        HybridIntegerationIntegrationLogger.LogEntry e = new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER);
        e.success = false;
        e.endpoint = 'a'.repeat(400);
        e.correlationId = 'c'.repeat(300);
        e.statusCode = 429;
        e.errorMessage = 'HTTP_RATE_LIMIT: too many requests';
        Id logId = HybridIntegerationIntegrationLogger.log(e);
        Assert.isNotNull(logId);
        Integration_Log__c row = [SELECT Status__c, Endpoint__c, Correlation_ID__c, Request_Time__c, Error_Message__c
            FROM Integration_Log__c WHERE Id = :logId];
        Assert.areEqual('Failed', row.Status__c);
        Assert.areEqual(255, row.Endpoint__c.length());
        Assert.areEqual(100, row.Correlation_ID__c.length());
        Assert.isNotNull(row.Request_Time__c, 'Request time defaults to now when absent');
        Assert.areEqual('HTTP_RATE_LIMIT: too many requests', row.Error_Message__c);
    }

    @IsTest
    static void loggingFailureDoesNotThrow() {
        HybridIntegerationIntegrationLogger.forceFailure = true;
        HybridIntegerationIntegrationLogger.LogEntry e = new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER);
        Id logId = HybridIntegerationIntegrationLogger.log(e);
        Assert.isNull(logId);
        Assert.isNotNull(HybridIntegerationIntegrationLogger.lastLoggingError);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }

    @IsTest
    static void nullEntryIsIgnored() {
        Assert.isNull(HybridIntegerationIntegrationLogger.log(null));
    }

    @IsTest
    static void integrationNameIsConfigurable() {
        Set<String> picklistValues = new Set<String>();
        for (Schema.PicklistEntry pe : Integration_Log__c.Integeration_Name__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                picklistValues.add(pe.getValue());
            }
        }
        List<String> names = new List<String>{
            HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER, HybridIntegerationIntegrationLogger.OPEN_METEO_AIR_QUALITY, HybridIntegerationIntegrationLogger.OPENAQ,
            HybridIntegerationIntegrationLogger.API_NINJAS_HOLIDAYS, HybridIntegerationIntegrationLogger.SPOTIFY, HybridIntegerationIntegrationLogger.FASTAPI
        };
        Integer verified = 0;
        for (String name : names) {
            if (!picklistValues.contains(name)) {
                continue; // value not yet present in this org's picklist (e.g. API Ninjas Holidays before the rename is deployed)
            }
            Id logId = HybridIntegerationIntegrationLogger.log(new HybridIntegerationIntegrationLogger.LogEntry(name));
            Assert.isNotNull(logId, 'Log failed for ' + name + ': ' + HybridIntegerationIntegrationLogger.lastLoggingError);
            Assert.areEqual(name, [SELECT Integeration_Name__c FROM Integration_Log__c WHERE Id = :logId].Integeration_Name__c);
            verified++;
        }
        Assert.isTrue(verified >= 5, 'Expected at least the 5 existing picklist values to be verified, got ' + verified);
    }

    @IsTest
    static void unsupportedOrBlankNameIsNotLogged() {
        Assert.isNull(HybridIntegerationIntegrationLogger.log(new HybridIntegerationIntegrationLogger.LogEntry('Made Up API')));
        Assert.isNotNull(HybridIntegerationIntegrationLogger.lastLoggingError);
        Assert.isNull(HybridIntegerationIntegrationLogger.log(new HybridIntegerationIntegrationLogger.LogEntry(null)));
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }
}
