@IsTest
private class HybridIntegerationHolidayResponseTest {
    @IsTest
    static void parsesAllDocumentedFields() {
        String body = HybridIntegerationTestSupport.holidayArray(new List<String>{
            HybridIntegerationTestSupport.holidayItem('CA', '2026-07-01', 'Canada Day', 'PUBLIC_HOLIDAY'),
            HybridIntegerationTestSupport.holidayItem('CA', '2026-09-07', 'Labour Day', 'PUBLIC_HOLIDAY')
        });
        HybridIntegerationHolidayResponse r = HybridIntegerationHolidayResponse.parse(body);
        Assert.areEqual(2, r.holidays.size());
        HybridIntegerationHolidayResponse.Holiday h = r.holidays[0];
        Assert.areEqual('Test Country', h.country);
        Assert.areEqual('CA', h.iso);
        Assert.areEqual(2026, h.year);
        Assert.areEqual('2026-07-01', h.date_x);
        Assert.areEqual('Monday', h.day);
        Assert.areEqual('Canada Day', h.name);
        Assert.areEqual('PUBLIC_HOLIDAY', h.type_x);
    }

    @IsTest
    static void emptyArrayIsValid() {
        Assert.areEqual(0, HybridIntegerationHolidayResponse.parse('[]').holidays.size());
    }

    @IsTest
    static void missingFieldsStayNullAndUnknownFieldsAreIgnored() {
        HybridIntegerationHolidayResponse r = HybridIntegerationHolidayResponse.parse('[{"name":"Only Name","federal":true,"regions":["x"]}]');
        Assert.areEqual('Only Name', r.holidays[0].name);
        Assert.isNull(r.holidays[0].iso);
        Assert.isNull(r.holidays[0].date_x);
        Assert.isNull(r.holidays[0].type_x);
    }

    @IsTest
    static void blankBodyThrows() {
        assertCode('', HybridIntegerationIntegrationException.EMPTY_RESPONSE);
        assertCode(null, HybridIntegerationIntegrationException.EMPTY_RESPONSE);
    }

    @IsTest
    static void malformedOrNonArrayJsonThrows() {
        assertCode('[{"name": "x"', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('not json', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('{"error":"Invalid country"}', HybridIntegerationIntegrationException.MALFORMED_JSON);
        assertCode('null', HybridIntegerationIntegrationException.MALFORMED_JSON);
    }

    private static void assertCode(String body, String expected) {
        try {
            HybridIntegerationHolidayResponse.parse(body);
            Assert.fail('Expected ' + expected);
        } catch (HybridIntegerationIntegrationException e) {
            Assert.areEqual(expected, e.errorCode);
        }
    }
}
