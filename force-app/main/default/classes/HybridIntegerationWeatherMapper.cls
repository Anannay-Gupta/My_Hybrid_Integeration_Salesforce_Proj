/**
 * Maps the Open-Meteo DTO to Weather_Snapshot__c. No DML, no callouts.
 */
public with sharing class HybridIntegerationWeatherMapper {
    public static final String FORECAST_TYPE_CURRENT = 'Current';
    public static final String DATA_SOURCE = 'Open-Meteo';

    private static final Pattern API_TIME = Pattern.compile('^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2}))?$');

    public static Weather_Snapshot__c toSnapshot(HybridIntegerationWeatherResponse dto, Id locationId) {
        if (dto == null || dto.current == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MISSING_CURRENT,
                'Cannot map a null weather response or null current block.',
                'The weather service returned no current weather data.'
            );
        }
        if (locationId == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.LOCATION_NOT_FOUND,
                'Cannot map a snapshot without a Location_Profile__c Id.',
                'No location was selected.'
            );
        }
        Weather_Snapshot__c snap = new Weather_Snapshot__c();
        snap.Location__c = locationId;
        snap.Temperature__c = scale(dto.current.temperature_2m);
        snap.Humidity__c = scale(dto.current.relative_humidity_2m);
        snap.Wind_Speed__c = scale(dto.current.wind_speed_10m);
        snap.Precipitation__c = scale(dto.current.precipitation);
        snap.Recorded_At__c = parseApiTime(dto.current.time_x, dto.utc_offset_seconds);
        snap.Forecast_Type__c = FORECAST_TYPE_CURRENT;
        snap.Data_Source__c = DATA_SOURCE;
        return snap;
    }

    /**
     * Open-Meteo returns LOCAL time of the location (timezone=auto) with no offset, e.g. "2026-11-12T14:30",
     * plus utc_offset_seconds. The true instant is local - offset. Building it with newInstanceGmt avoids the
     * running user's timezone shifting the value; Salesforce then displays it in each user's own timezone.
     */
    public static Datetime parseApiTime(String localTime, Integer utcOffsetSeconds) {
        if (String.isBlank(localTime) || utcOffsetSeconds == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.INVALID_TIMESTAMP,
                'Missing current.time or utc_offset_seconds (time=' + localTime + ', offset=' + utcOffsetSeconds + ').',
                'The weather service returned an invalid timestamp.'
            );
        }
        Matcher m = API_TIME.matcher(localTime.trim());
        if (!m.matches()) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.INVALID_TIMESTAMP,
                'Unrecognised current.time format: ' + localTime,
                'The weather service returned an invalid timestamp.'
            );
        }
        Integer seconds = String.isBlank(m.group(6)) ? 0 : Integer.valueOf(m.group(6));
        Datetime localAsGmt = Datetime.newInstanceGmt(
            Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), Integer.valueOf(m.group(3)),
            Integer.valueOf(m.group(4)), Integer.valueOf(m.group(5)), seconds
        );
        return localAsGmt.addSeconds(-utcOffsetSeconds);
    }

    private static Decimal scale(Decimal value) {
        return value == null ? null : value.setScale(2, System.RoundingMode.HALF_UP);
    }
}
