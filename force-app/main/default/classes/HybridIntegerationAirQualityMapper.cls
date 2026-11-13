/**
 * Maps the Air Quality DTO to Air_Quality_Reading__c. No DML, no callouts.
 * Conversions:
 *  - Pollutants (ug/m3) -> Number(10,2): setScale(2, HALF_UP).
 *  - AQI -> Number(6,0): Open-Meteo returns whole-number AQI values, so this is normally lossless. If a fractional
 *    AQI ever arrives it is rounded HALF_UP to a whole number (never truncated).
 *  - Timestamp: reuses WeatherMapper.parseApiTime (local time + utc_offset_seconds -> correct UTC instant).
 * Station__c is intentionally left empty (coordinate-based data, no physical station).
 */
public with sharing class HybridIntegerationAirQualityMapper {
    public static final String DATA_SOURCE = 'Open-Meteo';
    public static final String MEASUREMENT_TYPE = 'Forecast';

    public static Air_Quality_Reading__c toReading(HybridIntegerationAirQualityResponse dto, Id locationId) {
        if (dto == null || dto.current == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MISSING_CURRENT,
                'Cannot map a null air quality response or null current block.',
                'The air quality service returned no current measurements.'
            );
        }
        if (locationId == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.LOCATION_NOT_FOUND,
                'Cannot map a reading without a Location_Profile__c Id.',
                'No location was selected.'
            );
        }
        Air_Quality_Reading__c reading = new Air_Quality_Reading__c();
        reading.Location__c = locationId;
        reading.PM25__c = scalePollutant(dto.current.pm2_5);
        reading.PM10__c = scalePollutant(dto.current.pm10);
        reading.US_AQI__c = toWholeNumber(dto.current.us_aqi);
        reading.European_AQI__c = toWholeNumber(dto.current.european_aqi);
        reading.Ozone__c = scalePollutant(dto.current.ozone);
        reading.Nitrogen_Dioxide__c = scalePollutant(dto.current.nitrogen_dioxide);
        reading.Recorded_At__c = HybridIntegerationWeatherMapper.parseApiTime(dto.current.time_x, dto.utc_offset_seconds);
        reading.Data_Source__c = DATA_SOURCE;
        reading.Measurement_Type__c = MEASUREMENT_TYPE;
        return reading;
    }

    private static Decimal scalePollutant(Decimal value) {
        return value == null ? null : value.setScale(2, System.RoundingMode.HALF_UP);
    }

    private static Decimal toWholeNumber(Decimal value) {
        return value == null ? null : value.setScale(0, System.RoundingMode.HALF_UP);
    }
}
