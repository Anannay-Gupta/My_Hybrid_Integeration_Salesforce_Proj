/**
 * Typed DTO for the Open-Meteo Air Quality /v1/air-quality response (current block only).
 * Units (from current_units): pm2_5, pm10, ozone, nitrogen_dioxide = ug/m3; us_aqi = US AQI index; european_aqi = EAQI index.
 * The JSON key "time" is rewritten to "time_x" before deserialization ("time" clashes with an Apex type name).
 * AQI values are held as Decimal so a fractional value would be detected rather than silently truncated by JSON parsing.
 */
public with sharing class HybridIntegerationAirQualityResponse {
    public Decimal latitude;
    public Decimal longitude;
    public Integer utc_offset_seconds;
    public String timezone;
    public CurrentAirQuality current;

    public class CurrentAirQuality {
        public String time_x;            // local time in the response timezone, e.g. 2026-11-12T14:30
        public Integer interval;
        public Decimal pm2_5;            // ug/m3
        public Decimal pm10;             // ug/m3
        public Decimal us_aqi;           // index
        public Decimal european_aqi;     // index
        public Decimal ozone;            // ug/m3
        public Decimal nitrogen_dioxide; // ug/m3
    }

    public static HybridIntegerationAirQualityResponse parse(String body) {
        if (String.isBlank(body)) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.EMPTY_RESPONSE,
                'Open-Meteo Air Quality returned an empty response body.',
                'The air quality service returned no data.'
            );
        }
        String prepared = body.replaceAll('"time"\\s*:', '"time_x":');
        HybridIntegerationAirQualityResponse result;
        try {
            result = (HybridIntegerationAirQualityResponse) JSON.deserialize(prepared, HybridIntegerationAirQualityResponse.class);
        } catch (JSONException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Could not parse Open-Meteo Air Quality JSON: ' + e.getMessage(),
                'The air quality service returned an unreadable response.'
            );
        } catch (TypeException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Unexpected Open-Meteo Air Quality JSON structure: ' + e.getMessage(),
                'The air quality service returned an unreadable response.'
            );
        }
        if (result == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MALFORMED_JSON,
                'Open-Meteo Air Quality JSON deserialized to null.',
                'The air quality service returned an unreadable response.'
            );
        }
        return result;
    }

    /** True when a current block has a timestamp and at least one measurement. */
    public Boolean hasCurrentData() {
        return current != null
            && String.isNotBlank(current.time_x)
            && (current.pm2_5 != null || current.pm10 != null || current.us_aqi != null
                || current.european_aqi != null || current.ozone != null || current.nitrogen_dioxide != null);
    }
}
