/**
 * API Ninjas holiday -> Public_Holiday__c. No DML, no callouts. Single source of truth for category mapping.
 * Location__c is left null and Is_Global__c is never touched. The v2 response has no state/region data.
 */
public with sharing class HybridIntegerationHolidayMapper {
    public static final String RELIGIOUS = 'Religious';
    public static final Integer EXTERNAL_ID_MAX_LENGTH = 150;
    public static final Integer NAME_MAX_LENGTH = 80;     // standard Name field limit
    public static final Integer MAX_WARNINGS = 20;

    private static final Map<String, String> API_TO_SALESFORCE = new Map<String, String>{
        'PUBLIC_HOLIDAY' => 'Public',
        'BANK_HOLIDAY' => 'Bank',
        'STATE_HOLIDAY' => 'State',
        'LOCAL_HOLIDAY' => 'Local',
        'PROVINCE_TERRITORY_HOLIDAY' => 'Province_Territory',
        'GOVERNMENT_HOLIDAY' => 'Government',
        'PRIVATE_SECTOR_HOLIDAY' => 'Private',
        'OBSERVANCE' => 'Observance',
        'OPTIONAL_HOLIDAY' => 'Optional',
        'CHRISTIAN_HOLIDAY' => RELIGIOUS,
        'ORTHODOX_HOLIDAY' => RELIGIOUS,
        'MUSLIM_HOLIDAY' => RELIGIOUS,
        'JEWISH_HOLIDAY' => RELIGIOUS,
        'HINDU_HOLIDAY' => RELIGIOUS
    };

    private static final List<String> RELIGIOUS_API_TYPES = new List<String>{
        'CHRISTIAN_HOLIDAY', 'ORTHODOX_HOLIDAY', 'MUSLIM_HOLIDAY', 'JEWISH_HOLIDAY', 'HINDU_HOLIDAY'
    };

    // Holiday_Type__c API values (note Province_Territory, not the label "Province/Territory")
    private static final List<String> SALESFORCE_CATEGORIES = new List<String>{
        'Public', 'Bank', 'State', 'Local', 'Province_Territory', 'Government', 'Private', 'Observance', 'Optional', RELIGIOUS
    };

    public class MappingResult {
        public List<Public_Holiday__c> records = new List<Public_Holiday__c>();
        public List<String> warnings = new List<String>();
        public Integer skippedCount = 0;
        public Integer duplicateCount = 0;
    }

    public static List<String> supportedCategories() {
        return SALESFORCE_CATEGORIES.clone();
    }

    /** Returns the canonical Holiday_Type__c value (case-insensitive match on the API value) or throws. */
    public static String normalizeCategory(String category) {
        if (String.isNotBlank(category)) {
            String trimmed = category.trim();
            for (String supported : SALESFORCE_CATEGORIES) {
                if (supported.equalsIgnoreCase(trimmed)) {
                    return supported;
                }
            }
        }
        throw new HybridIntegerationIntegrationException(
            HybridIntegerationIntegrationException.INVALID_CATEGORY,
            'Unsupported or blank holiday category: ' + category,
            'Please choose a supported holiday category.'
        );
    }

    /** API categories to request for a Salesforce category (five for Religious, one otherwise). */
    public static List<String> apiTypesFor(String category) {
        String canonical = normalizeCategory(category);
        if (canonical == RELIGIOUS) {
            return RELIGIOUS_API_TYPES.clone();
        }
        for (String apiType : API_TO_SALESFORCE.keySet()) {
            if (API_TO_SALESFORCE.get(apiType) == canonical) {
                return new List<String>{ apiType };
            }
        }
        throw new HybridIntegerationIntegrationException(
            HybridIntegerationIntegrationException.INVALID_CATEGORY, 'No API category mapped for ' + canonical, 'Please choose a supported holiday category.');
    }

    /** Salesforce picklist value for an API category, or null when the API category is not supported. */
    public static String toSalesforceType(String apiType) {
        return String.isBlank(apiType) ? null : API_TO_SALESFORCE.get(apiType.trim().toUpperCase());
    }

    public static String normalizeName(String name) {
        return String.isBlank(name) ? '' : name.trim().toLowerCase().replaceAll('\\s+', ' ');
    }

    /**
     * Deterministic key: ISO|date|API category|normalized name. If longer than 150 characters, the name part
     * is replaced by its SHA-256 hex digest (64 chars), which always fits.
     */
    public static String buildExternalId(String iso, Date holidayDate, String apiType, String name) {
        String prefix = iso.toUpperCase() + '|' + String.valueOf(holidayDate) + '|' + apiType.trim().toUpperCase() + '|';
        String normalized = normalizeName(name);
        String raw = prefix + normalized;
        if (raw.length() <= EXTERNAL_ID_MAX_LENGTH) {
            return raw;
        }
        return prefix + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(normalized)));
    }

    /** Maps one API entry; throws INVALID_RECORD when required data is missing or unsupported. */
    public static Public_Holiday__c toHoliday(HybridIntegerationHolidayResponse.Holiday item) {
        if (item == null) {
            throw invalid('entry is null');
        }
        if (String.isBlank(item.name)) {
            throw invalid('missing name');
        }
        if (String.isBlank(item.iso) || !Pattern.matches('[A-Za-z]{2}', item.iso.trim())) {
            throw invalid('missing or invalid iso "' + item.iso + '"');
        }
        Date holidayDate = parseDate(item.date_x);
        String salesforceType = toSalesforceType(item.type_x);
        if (salesforceType == null) {
            throw invalid('unsupported type "' + item.type_x + '"');
        }
        String iso = item.iso.trim().toUpperCase();
        Public_Holiday__c record = new Public_Holiday__c();
        record.Name = item.name.trim().left(NAME_MAX_LENGTH);
        record.Holiday_Date__c = holidayDate;
        record.Country_Code__c = iso;
        record.Holiday_Type__c = salesforceType;
        record.External_Holiday_ID__c = buildExternalId(iso, holidayDate, item.type_x, item.name);
        return record;
    }

    /**
     * Maps a batch. Invalid entries, entries whose type does not match the requested Salesforce category, and
     * duplicates within the batch are skipped and reported (never silently dropped).
     */
    public static MappingResult toHolidays(List<HybridIntegerationHolidayResponse.Holiday> items, String requestedCategory) {
        MappingResult result = new MappingResult();
        if (items == null) {
            return result;
        }
        String expected = String.isBlank(requestedCategory) ? null : normalizeCategory(requestedCategory);
        Set<String> seen = new Set<String>();
        Integer index = 0;
        for (HybridIntegerationHolidayResponse.Holiday item : items) {
            index++;
            try {
                Public_Holiday__c record = toHoliday(item);
                if (expected != null && record.Holiday_Type__c != expected) {
                    throw invalid('type "' + item.type_x + '" does not belong to requested category ' + expected);
                }
                if (!seen.add(record.External_Holiday_ID__c)) {
                    result.duplicateCount++;
                    continue;
                }
                result.records.add(record);
            } catch (HybridIntegerationIntegrationException e) {
                result.skippedCount++;
                if (result.warnings.size() < MAX_WARNINGS) {
                    result.warnings.add('Entry ' + index + ' skipped: ' + e.getMessage());
                }
            }
        }
        return result;
    }

    private static Date parseDate(String text) {
        if (String.isBlank(text) || !Pattern.matches('\\d{4}-\\d{2}-\\d{2}', text.trim())) {
            throw invalid('missing or invalid date "' + text + '"');
        }
        try {
            Date parsed = Date.valueOf(text.trim());
            if (String.valueOf(parsed) != text.trim()) {
                throw invalid('date does not exist "' + text + '"');
            }
            return parsed;
        } catch (TypeException e) {
            throw invalid('invalid date "' + text + '"');
        }
    }

    private static HybridIntegerationIntegrationException invalid(String detail) {
        return new HybridIntegerationIntegrationException(
            HybridIntegerationIntegrationException.INVALID_RECORD,
            'Invalid holiday data: ' + detail,
            'Some holiday entries were invalid and were skipped.'
        );
    }
}
