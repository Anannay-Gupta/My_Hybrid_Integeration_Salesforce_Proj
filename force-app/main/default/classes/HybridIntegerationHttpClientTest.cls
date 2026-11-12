@IsTest
private class HybridIntegerationHttpClientTest {
    @IsTest
    static void sendsRequestAndReturnsResponse() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, '{"ok":true}'));
        Test.startTest();
        HttpResponse res = HybridIntegerationHttpClient.send('callout:Any/path', 'get',
            new Map<String, String>{ 'Accept' => 'application/json' }, 5000);
        Test.stopTest();
        Assert.areEqual(200, res.getStatusCode());
        Assert.areEqual('GET', HybridIntegerationTestSupport.lastRequest.getMethod());
        Assert.areEqual('application/json', HybridIntegerationTestSupport.lastRequest.getHeader('Accept'));
        Assert.areEqual(1, HybridIntegerationTestSupport.callCount);
    }

    @IsTest
    static void defaultsToGetWhenMethodBlank() {
        HybridIntegerationTestSupport.reset();
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock(200, '{}'));
        Test.startTest();
        HybridIntegerationHttpClient.send('callout:Any/path', null, null, null);
        Test.stopTest();
        Assert.areEqual('GET', HybridIntegerationTestSupport.lastRequest.getMethod());
    }

    @IsTest
    static void timeoutIsTranslated() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock('Read timed out'));
        Test.startTest();
        try {
            HybridIntegerationHttpClient.send('callout:Any/path', 'GET', null, 1000);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.TIMEOUT, e.errorCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void otherCalloutExceptionIsTranslated() {
        Test.setMock(HttpCalloutMock.class, new HybridIntegerationTestSupport.Mock('Unauthorized endpoint'));
        Test.startTest();
        try {
            HybridIntegerationHttpClient.send('callout:Any/path', 'GET', null, null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.CALLOUT_FAILED, e.errorCode);
            Assert.isFalse(e.getSafeMessage().contains('Unauthorized endpoint'), 'Internal detail must not be in the user message');
        }
        Test.stopTest();
    }

    @IsTest
    static void blankEndpointRejectedWithoutCallout() {
        HybridIntegerationTestSupport.reset();
        try {
            HybridIntegerationHttpClient.send('  ', 'GET', null, null);
            Assert.fail('Expected exception');
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(HybridIntegerationIntegrationException.CALLOUT_FAILED, e.errorCode);
        }
        Assert.areEqual(0, HybridIntegerationTestSupport.callCount);
    }
}
