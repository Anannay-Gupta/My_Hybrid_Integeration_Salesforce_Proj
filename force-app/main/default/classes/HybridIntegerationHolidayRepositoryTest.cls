@IsTest
private class HybridIntegerationHolidayRepositoryTest {
    private static Public_Holiday__c holiday(String name, String dateText, String apiType) {
        return HybridIntegerationHolidayMapper.toHoliday(HybridIntegerationHolidayResponse.parse(
            '[' + HybridIntegerationTestSupport.holidayItem('US', dateText, name, apiType) + ']').holidays[0]);
    }

    @IsTest
    static void upsertCreatesThenRepeatedUpsertDoesNotDuplicate() {
        HybridIntegerationHolidayRepository.UpsertSummary first = HybridIntegerationHolidayRepository.upsertHolidays(
            new List<Public_Holiday__c>{ holiday('Independence Day', '2026-07-04', 'PUBLIC_HOLIDAY'), holiday('Thanksgiving', '2026-11-26', 'PUBLIC_HOLIDAY') });
        Assert.areEqual(2, first.insertedCount);
        Assert.areEqual(0, first.updatedCount);
        Assert.areEqual(2, [SELECT COUNT() FROM Public_Holiday__c]);

        // same keys again, one with a changed Name -> updated, no new rows
        Public_Holiday__c renamed = holiday('Independence Day', '2026-07-04', 'PUBLIC_HOLIDAY');
        renamed.Name = 'Independence Day (renamed)';
        HybridIntegerationHolidayRepository.UpsertSummary second = HybridIntegerationHolidayRepository.upsertHolidays(
            new List<Public_Holiday__c>{ renamed, holiday('Thanksgiving', '2026-11-26', 'PUBLIC_HOLIDAY') });
        Assert.areEqual(0, second.insertedCount);
        Assert.areEqual(2, second.updatedCount);
        Assert.areEqual(2, [SELECT COUNT() FROM Public_Holiday__c]);
        Assert.areEqual(1, [SELECT COUNT() FROM Public_Holiday__c WHERE Name = 'Independence Day (renamed)']);
    }

    @IsTest
    static void existingRecordsAreNeverDeleted() {
        HybridIntegerationHolidayRepository.upsertHolidays(new List<Public_Holiday__c>{ holiday('Old Holiday', '2026-02-02', 'OBSERVANCE') });
        HybridIntegerationHolidayRepository.upsertHolidays(new List<Public_Holiday__c>{ holiday('New Holiday', '2026-03-03', 'OBSERVANCE') });
        Assert.areEqual(2, [SELECT COUNT() FROM Public_Holiday__c]);
    }

    @IsTest
    static void partialFailureSavesValidRecordsAndReportsErrors() {
        Public_Holiday__c bad = holiday('Broken', '2026-05-05', 'PUBLIC_HOLIDAY');
        bad.Name = 'x'.repeat(81);   // Name max length is 80 -> this row fails with STRING_TOO_LONG
        HybridIntegerationHolidayRepository.UpsertSummary s = HybridIntegerationHolidayRepository.upsertHolidays(
            new List<Public_Holiday__c>{ holiday('Good One', '2026-04-04', 'PUBLIC_HOLIDAY'), bad });
        Assert.areEqual(1, s.savedCount());
        Assert.areEqual(1, s.failedCount);
        Assert.areEqual(1, s.errors.size());
        Assert.isTrue(s.errors[0].contains('STRING_TOO_LONG'), s.errors[0]);
        Assert.areEqual(1, [SELECT COUNT() FROM Public_Holiday__c]);
    }

    @IsTest
    static void bulkUpsertOf200Records() {
        List<Public_Holiday__c> records = new List<Public_Holiday__c>();
        for (Integer i = 0; i < 200; i++) {
            records.add(holiday('Holiday ' + i, '2026-01-01', 'PUBLIC_HOLIDAY'));
        }
        HybridIntegerationHolidayRepository.UpsertSummary s = HybridIntegerationHolidayRepository.upsertHolidays(records);
        Assert.areEqual(200, s.insertedCount);
        Assert.areEqual(0, s.failedCount);
    }

    @IsTest
    static void emptyAndNullInputsAreNoOps() {
        Assert.areEqual(0, HybridIntegerationHolidayRepository.upsertHolidays(null).savedCount());
        Assert.areEqual(0, HybridIntegerationHolidayRepository.upsertHolidays(new List<Public_Holiday__c>()).savedCount());
    }
}
