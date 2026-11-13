@IsTest
private class HybridIntegerationHolidayMapperTest {
    private static HybridIntegerationHolidayResponse.Holiday item(String iso, String dateText, String name, String apiType) {
        return HybridIntegerationHolidayResponse.parse('[' + HybridIntegerationTestSupport.holidayItem(iso, dateText, name, apiType) + ']').holidays[0];
    }

    @IsTest
    static void mapsAll14ApiCategoriesToSalesforcePicklistValues() {
        Map<String, String> expected = new Map<String, String>{
            'PUBLIC_HOLIDAY' => 'Public', 'BANK_HOLIDAY' => 'Bank', 'STATE_HOLIDAY' => 'State',
            'LOCAL_HOLIDAY' => 'Local', 'PROVINCE_TERRITORY_HOLIDAY' => 'Province_Territory',
            'GOVERNMENT_HOLIDAY' => 'Government', 'PRIVATE_SECTOR_HOLIDAY' => 'Private',
            'OBSERVANCE' => 'Observance', 'OPTIONAL_HOLIDAY' => 'Optional',
            'CHRISTIAN_HOLIDAY' => 'Religious', 'ORTHODOX_HOLIDAY' => 'Religious', 'MUSLIM_HOLIDAY' => 'Religious',
            'JEWISH_HOLIDAY' => 'Religious', 'HINDU_HOLIDAY' => 'Religious'
        };
        Assert.areEqual(14, expected.size());
        for (String apiType : expected.keySet()) {
            Assert.areEqual(expected.get(apiType), HybridIntegerationHolidayMapper.toSalesforceType(apiType), apiType);
            Assert.areEqual(expected.get(apiType), HybridIntegerationHolidayMapper.toHoliday(item('US', '2026-03-01', 'X', apiType)).Holiday_Type__c);
        }
    }

    @IsTest
    static void unsupportedApiCategoriesAreNotMapped() {
        for (String apiType : new List<String>{ 'DE_FACTO_HOLIDAY', 'SUBSTITUTE_HOLIDAY', 'FLAG_DAY', 'SEASON', 'nonsense', '', null }) {
            Assert.isNull(HybridIntegerationHolidayMapper.toSalesforceType(apiType), 'apiType=' + apiType);
        }
    }

    @IsTest
    static void apiTypesForEachSalesforceCategory() {
        Map<String, String> single = new Map<String, String>{
            'Public' => 'PUBLIC_HOLIDAY', 'Bank' => 'BANK_HOLIDAY', 'State' => 'STATE_HOLIDAY', 'Local' => 'LOCAL_HOLIDAY',
            'Province_Territory' => 'PROVINCE_TERRITORY_HOLIDAY', 'Government' => 'GOVERNMENT_HOLIDAY',
            'Private' => 'PRIVATE_SECTOR_HOLIDAY', 'Observance' => 'OBSERVANCE', 'Optional' => 'OPTIONAL_HOLIDAY'
        };
        for (String sf : single.keySet()) {
            Assert.areEqual(new List<String>{ single.get(sf) }, HybridIntegerationHolidayMapper.apiTypesFor(sf), sf);
        }
        Assert.areEqual(
            new List<String>{ 'CHRISTIAN_HOLIDAY', 'ORTHODOX_HOLIDAY', 'MUSLIM_HOLIDAY', 'JEWISH_HOLIDAY', 'HINDU_HOLIDAY' },
            HybridIntegerationHolidayMapper.apiTypesFor('Religious'));
        Assert.areEqual(10, HybridIntegerationHolidayMapper.supportedCategories().size());
    }

    @IsTest
    static void categoryValidation() {
        Assert.areEqual('Province_Territory', HybridIntegerationHolidayMapper.normalizeCategory(' province_territory '));
        for (String bad : new List<String>{ null, '', '  ', 'Federal', 'Province/Territory', 'PUBLIC_HOLIDAY' }) {
            try {
                HybridIntegerationHolidayMapper.normalizeCategory(bad);
                Assert.fail('Expected rejection of ' + bad);
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.INVALID_CATEGORY, e.errorCode);
            }
        }
    }

    @IsTest
    static void mapsFieldsAndLeavesLocationAndGlobalUntouched() {
        Public_Holiday__c h = HybridIntegerationHolidayMapper.toHoliday(item('gb', '2026-12-25', '  Christmas Day ', 'PUBLIC_HOLIDAY'));
        Assert.areEqual('Christmas Day', h.Name);
        Assert.areEqual(Date.newInstance(2026, 12, 25), h.Holiday_Date__c);
        Assert.areEqual('GB', h.Country_Code__c);
        Assert.areEqual('Public', h.Holiday_Type__c);
        Assert.isNull(h.Location__c);
        Assert.areEqual(false, h.Is_Global__c, 'Is_Global__c is never populated');
        Assert.areEqual('GB|2026-12-25|PUBLIC_HOLIDAY|christmas day', h.External_Holiday_ID__c);
    }

    @IsTest
    static void externalIdIsDeterministicAndNormalized() {
        Date d = Date.newInstance(2026, 1, 1);
        String a = HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'New Year\'s Day');
        Assert.areEqual(a, HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'New Year\'s Day'));
        Assert.areEqual(a, HybridIntegerationHolidayMapper.buildExternalId('us', d, 'public_holiday', '  NEW   YEAR\'S  day '));
        Assert.areNotEqual(a, HybridIntegerationHolidayMapper.buildExternalId('CA', d, 'PUBLIC_HOLIDAY', 'New Year\'s Day'));
        Assert.areNotEqual(a, HybridIntegerationHolidayMapper.buildExternalId('US', d.addDays(1), 'PUBLIC_HOLIDAY', 'New Year\'s Day'));
        Assert.areNotEqual(a, HybridIntegerationHolidayMapper.buildExternalId('US', d, 'BANK_HOLIDAY', 'New Year\'s Day'));
        Assert.areNotEqual(a, HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'Other'));
    }

    @IsTest
    static void externalIdLengthBoundary() {
        Date d = Date.newInstance(2026, 1, 1);
        // prefix 'US|2026-01-01|PUBLIC_HOLIDAY|' is 29 chars: 121-char name -> exactly 150 -> kept readable
        String exact = HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'a'.repeat(121));
        Assert.areEqual(150, exact.length());
        Assert.isTrue(exact.endsWith('a'.repeat(121)));
        // 122 chars -> 151 raw -> name replaced by SHA-256 hex (64 chars)
        String hashed = HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'a'.repeat(122));
        Assert.areEqual(29 + 64, hashed.length());
        Assert.isTrue(hashed.startsWith('US|2026-01-01|PUBLIC_HOLIDAY|'));
        Assert.areEqual(hashed, HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PUBLIC_HOLIDAY', 'a'.repeat(122)), 'stable');
        // very long name still fits
        String huge = HybridIntegerationHolidayMapper.buildExternalId('US', d, 'PROVINCE_TERRITORY_HOLIDAY', 'b'.repeat(5000));
        Assert.isTrue(huge.length() <= 150);
    }

    @IsTest
    static void longNamesAreTruncatedForNameFieldOnly() {
        Public_Holiday__c h = HybridIntegerationHolidayMapper.toHoliday(item('US', '2026-01-01', 'n'.repeat(200), 'PUBLIC_HOLIDAY'));
        Assert.areEqual(80, h.Name.length());
        Assert.isTrue(h.External_Holiday_ID__c.length() <= 150);
    }

    @IsTest
    static void religiousRecordsKeepOriginalApiCategoryInExternalId() {
        Public_Holiday__c a = HybridIntegerationHolidayMapper.toHoliday(item('IN', '2026-11-08', 'Festival', 'HINDU_HOLIDAY'));
        Public_Holiday__c b = HybridIntegerationHolidayMapper.toHoliday(item('IN', '2026-11-08', 'Festival', 'MUSLIM_HOLIDAY'));
        Assert.areEqual('Religious', a.Holiday_Type__c);
        Assert.areEqual('Religious', b.Holiday_Type__c);
        Assert.areNotEqual(a.External_Holiday_ID__c, b.External_Holiday_ID__c);
        Assert.isTrue(a.External_Holiday_ID__c.contains('HINDU_HOLIDAY'));
    }

    @IsTest
    static void invalidEntriesAreRejectedIndividually() {
        List<HybridIntegerationHolidayResponse.Holiday> bad = new List<HybridIntegerationHolidayResponse.Holiday>{
            null,
            HybridIntegerationHolidayResponse.parse('[{"iso":"US","date":"2026-01-01","type":"PUBLIC_HOLIDAY"}]').holidays[0],                 // no name
            HybridIntegerationHolidayResponse.parse('[{"name":"A","date":"2026-01-01","type":"PUBLIC_HOLIDAY"}]').holidays[0],                 // no iso
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"USA","date":"2026-01-01","type":"PUBLIC_HOLIDAY"}]').holidays[0],    // bad iso
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"US","type":"PUBLIC_HOLIDAY"}]').holidays[0],                          // no date
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"US","date":"01/02/2026","type":"PUBLIC_HOLIDAY"}]').holidays[0],      // bad format
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"US","date":"2026-02-30","type":"PUBLIC_HOLIDAY"}]').holidays[0],      // impossible date
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"US","date":"2026-01-01"}]').holidays[0],                              // no type
            HybridIntegerationHolidayResponse.parse('[{"name":"A","iso":"US","date":"2026-01-01","type":"FLAG_DAY"}]').holidays[0]             // unsupported type
        };
        for (HybridIntegerationHolidayResponse.Holiday h : bad) {
            try {
                HybridIntegerationHolidayMapper.toHoliday(h);
                Assert.fail('Expected INVALID_RECORD');
            } catch (HybridIntegerationIntegrationException e) {
                Assert.areEqual(HybridIntegerationIntegrationException.INVALID_RECORD, e.errorCode);
            }
        }
        HybridIntegerationHolidayMapper.MappingResult r = HybridIntegerationHolidayMapper.toHolidays(bad, null);
        Assert.areEqual(0, r.records.size());
        Assert.areEqual(bad.size(), r.skippedCount);
        Assert.areEqual(bad.size(), r.warnings.size());
    }

    @IsTest
    static void batchSkipsMismatchedTypesAndDuplicatesButKeepsValidEntries() {
        List<HybridIntegerationHolidayResponse.Holiday> items = new List<HybridIntegerationHolidayResponse.Holiday>{
            item('US', '2026-07-04', 'Independence Day', 'PUBLIC_HOLIDAY'),
            item('US', '2026-07-04', 'Independence Day', 'PUBLIC_HOLIDAY'),   // duplicate in same batch
            item('US', '2026-12-26', 'Boxing Day', 'BANK_HOLIDAY'),            // wrong category for a Public search
            item('US', '2026-11-26', 'Thanksgiving', 'PUBLIC_HOLIDAY')
        };
        HybridIntegerationHolidayMapper.MappingResult r = HybridIntegerationHolidayMapper.toHolidays(items, 'Public');
        Assert.areEqual(2, r.records.size());
        Assert.areEqual(1, r.duplicateCount);
        Assert.areEqual(1, r.skippedCount);
        Assert.isTrue(r.warnings[0].contains('does not belong'));
    }

    @IsTest
    static void nullOrEmptyBatchIsSafe() {
        Assert.areEqual(0, HybridIntegerationHolidayMapper.toHolidays(null, 'Public').records.size());
        Assert.areEqual(0, HybridIntegerationHolidayMapper.toHolidays(new List<HybridIntegerationHolidayResponse.Holiday>(), 'Public').records.size());
    }
}
