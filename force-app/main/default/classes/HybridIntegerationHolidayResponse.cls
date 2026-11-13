/**
 * Typed wrapper for the API Ninjas v2 /holidays response: a JSON array of
 * { country, iso, year, date, day, name, type }. No other fields are assumed.
 * The keys "date" and "type" are renamed to "date_x" / "type_x" before deserialization
 * because they collide with Apex type names.
 */
public with sharing class HybridIntegerationHolidayResponse {
    public List<Holiday> holidays = new List<Holiday>();

    public class Holiday {
        public String country;
        public String iso;
        public Integer year;
        public String date_x;   // YYYY-MM-DD
        public String day;
        public String name;
        public String type_x;   // e.g. PUBLIC_HOLIDAY
    }

    public static HybridIntegerationHolidayResponse parse(String body) {
        if (String.isBlank(body)) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.EMPTY_RESPONSE,
                'API Ninjas returned an empty response body.',
                'The holidays service returned no data.'
            );
        }
        String prepared = body.replaceAll('"date"\\s*:', '"date_x":').replaceAll('"type"\\s*:', '"type_x":');
        List<Holiday> items;
        try {
            items = (List<Holiday>) JSON.deserialize(prepared, List<Holiday>.class);
        } catch (JSONException e) {
            throw malformed('Could not parse API Ninjas JSON array: ' + e.getMessage());
        } catch (TypeException e) {
            throw malformed('Unexpected API Ninjas JSON structure: ' + e.getMessage());
        }
        if (items == null) {
            throw malformed('API Ninjas JSON deserialized to null.');
        }
        HybridIntegerationHolidayResponse result = new HybridIntegerationHolidayResponse();
        result.holidays = items;   // an empty array is valid: no holidays for that country/type
        return result;
    }

    private static HybridIntegerationIntegrationException malformed(String detail) {
        return new HybridIntegerationIntegrationException(
            HybridIntegerationIntegrationException.MALFORMED_JSON,
            detail,
            'The holidays service returned an unreadable response.'
        );
    }
}
