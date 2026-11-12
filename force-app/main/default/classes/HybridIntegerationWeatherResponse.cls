/**
 * Strongly typed DTO for the Open-Meteo /v1/forecast response (current weather only).
 * Property names intentionally match the JSON keys so JSON.deserialize works directly.
 * The JSON key "time" is renamed to "time_x" before deserialization (see parse()),
 * because "time" collides with an Apex system type name.
 */
public with sharing class HybridIntegerationWeatherResponse {
    public Decimal latitude;
    public Decimal longitude;
    public Integer utc_offset_seconds;
    public String timezone;
    public CurrentWeather current;

    public class CurrentWeather {
        public String time_x;                 // local time in the response timezone, e.g. 2026-11-12T14:30
        public Integer interval;
        public Decimal temperature_2m;        // deg C
        public Decimal relative_humidity_2m;  // %
        public Decimal precipitation;         // mm
        public Decimal wind_speed_10m;        // km/h
    }

    public static HybridIntegerationWeatherResponse parse(String body) {
        if (String.isBlank(body)) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.EMPTY_RESPONSE,
                'Open-Meteo returned an empty response body.',
                'The weather service returned no data.'
            );
        }
        String prepared = body.replaceAll('"time"\\s*:', '"time_x":');
        HybridIntegerationWeatherResponse result;
        try {
            result = (HybridIntegerationWeatherResponse) JSON.deserialize(prepared, HybridIntegerationWeatherResponse.class);
        } catch (JSONException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Could not parse Open-Meteo JSON: ' + e.getMessage(),
                'The weather service returned an unreadable response.'
            );
        } catch (TypeException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Unexpected Open-Meteo JSON structure: ' + e.getMessage(),
                'The weather service returned an unreadable response.'
            );
        }
        if (result == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Open-Meteo JSON deserialized to null.',
                'The weather service returned an unreadable response.'
            );
        }
        return result;
    }

    /** True when a current block with a timestamp and at least one measurement is present. */
    public Boolean hasCurrentData() {
        return current != null
            && String.isNotBlank(current.time_x)
            && (current.temperature_2m != null || current.relative_humidity_2m != null
                || current.precipitation != null || current.wind_speed_10m != null);
    }
}
