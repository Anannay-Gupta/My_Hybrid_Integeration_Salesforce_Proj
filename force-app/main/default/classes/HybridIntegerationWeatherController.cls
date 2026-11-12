/**
 * @AuraEnabled entry point for the future LWC.
 * Methods never throw to the client: they return a structured response. This matters for logging --
 * throwing AuraHandledException would roll back the whole transaction, including the Integration_Log__c row.
 * Order inside a transaction: SOQL -> callout -> DML (snapshot) -> DML (log). No callout after DML.
 */
public with sharing class HybridIntegerationWeatherController {

    public class WeatherApiResponse {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean saved = false;
        @AuraEnabled public String message;
        @AuraEnabled public String errorCode;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id locationId;
        @AuraEnabled public Id snapshotId;
        @AuraEnabled public Id logId;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String timezone;
        @AuraEnabled public Datetime recordedAt;
        @AuraEnabled public Decimal temperature;
        @AuraEnabled public Decimal humidity;
        @AuraEnabled public Decimal windSpeed;
        @AuraEnabled public Decimal precipitation;
    }

    /** Fetch current weather for display only (no snapshot saved). A log row is still written. */
    @AuraEnabled
    public static WeatherApiResponse getWeatherForLocation(Id locationId) {
        return execute(locationId, false);
    }

    /** Fetch current weather and save a Weather_Snapshot__c. */
    @AuraEnabled
    public static WeatherApiResponse fetchAndSaveWeather(Id locationId) {
        return execute(locationId, true);
    }

    private static WeatherApiResponse execute(Id locationId, Boolean saveSnapshot) {
        WeatherApiResponse out = new WeatherApiResponse();
        out.locationId = locationId;

        HybridIntegerationWeatherService.CallContext ctx = new HybridIntegerationWeatherService.CallContext();
        ctx.correlationId = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        out.correlationId = ctx.correlationId;

        String internalError = null;
        try {
            // 1) query + callout (no DML has happened yet)
            HybridIntegerationWeatherService.WeatherResult result = HybridIntegerationWeatherService.fetchForLocation(locationId, ctx);
            populate(out, result.weather);

            // 2) DML
            if (saveSnapshot) {
                Weather_Snapshot__c snap = HybridIntegerationWeatherMapper.toSnapshot(result.weather, result.locationId);
                out.snapshotId = HybridIntegerationWeatherRepository.save(snap);
                out.saved = true;
            }
            out.success = true;
            out.message = saveSnapshot ? 'Weather snapshot saved.' : 'Weather retrieved.';
        } catch (HybridIntegerationIntegrationException e) {
            out.errorCode = e.errorCode;
            out.message = e.getSafeMessage();
            internalError = e.errorCode + ': ' + e.getMessage();
            if (ctx.statusCode == null) {
                ctx.statusCode = e.httpStatus;
            }
        } catch (Exception e) {
            out.errorCode = HybridIntegerationIntegrationException.UNEXPECTED;
            out.message = 'An unexpected error occurred. Reference: ' + ctx.correlationId;
            internalError = e.getTypeName() + ': ' + e.getMessage(); // no stack trace
        }

        // 3) log (DML) - after callout, never throws
        HybridIntegerationIntegrationLogger.LogEntry entry = new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.OPEN_METEO_WEATHER);
        entry.success = out.success;
        entry.endpoint = ctx.endpoint;
        entry.httpMethod = ctx.httpMethod;
        entry.statusCode = ctx.statusCode;
        entry.requestTime = ctx.requestTime;
        entry.responseTime = ctx.responseTime;
        entry.durationMs = ctx.durationMs;
        entry.errorMessage = internalError;
        entry.correlationId = ctx.correlationId;
        entry.responseSummary = ctx.responseSummary;
        out.logId = HybridIntegerationIntegrationLogger.log(entry);
        return out;
    }

    private static void populate(WeatherApiResponse out, HybridIntegerationWeatherResponse w) {
        out.latitude = w.latitude;
        out.longitude = w.longitude;
        out.timezone = w.timezone;
        out.temperature = w.current.temperature_2m;
        out.humidity = w.current.relative_humidity_2m;
        out.windSpeed = w.current.wind_speed_10m;
        out.precipitation = w.current.precipitation;
        try {
            out.recordedAt = HybridIntegerationWeatherMapper.parseApiTime(w.current.time_x, w.utc_offset_seconds);
        } catch (HybridIntegerationIntegrationException e) {
            // surfaced by the mapper when saving; display-only calls simply omit the timestamp
            out.recordedAt = null;
        }
    }
}
