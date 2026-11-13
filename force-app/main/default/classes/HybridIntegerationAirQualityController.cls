/**
 * @AuraEnabled entry point for the future LWC. Never throws to the client (a thrown AuraHandledException would
 * roll back the Integration_Log__c row). Order per transaction: SOQL -> callout -> DML (reading) -> DML (log).
 */
public with sharing class HybridIntegerationAirQualityController {

    public class AirQualityApiResponse {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean saved = false;
        @AuraEnabled public Boolean found = false;
        @AuraEnabled public String message;
        @AuraEnabled public String errorCode;
        @AuraEnabled public String correlationId;
        @AuraEnabled public Id locationId;
        @AuraEnabled public Id readingId;
        @AuraEnabled public Id logId;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String timezone;
        @AuraEnabled public Datetime recordedAt;
        @AuraEnabled public Decimal pm25;
        @AuraEnabled public Decimal pm10;
        @AuraEnabled public Integer usAqi;
        @AuraEnabled public Integer europeanAqi;
        @AuraEnabled public Decimal ozone;
        @AuraEnabled public Decimal nitrogenDioxide;
    }

    /** Fetch current air quality for display only (no reading saved). A log row is still written. */
    @AuraEnabled
    public static AirQualityApiResponse getAirQualityForLocation(Id locationId) {
        return execute(locationId, false);
    }

    /** Fetch current air quality and save an Air_Quality_Reading__c. */
    @AuraEnabled
    public static AirQualityApiResponse fetchAndSaveAirQuality(Id locationId) {
        return execute(locationId, true);
    }

    /** Latest saved reading for a location. No callout, no integration log. */
    @AuraEnabled
    public static AirQualityApiResponse getLatestReading(Id locationId) {
        AirQualityApiResponse out = new AirQualityApiResponse();
        out.locationId = locationId;
        try {
            Location_Profile__c loc = HybridIntegerationWeatherService.getLocation(locationId);
            Air_Quality_Reading__c reading = HybridIntegerationAirQualityRepository.findLatestForLocation(loc.Id);
            out.success = true;
            if (reading == null) {
                out.message = 'No saved air quality readings for this location.';
            } else {
                out.found = true;
                out.readingId = reading.Id;
                populateMeasurements(out, reading);
                out.message = 'Latest saved reading returned.';
            }
        } catch (HybridIntegerationIntegrationException e) {
            out.errorCode = e.errorCode;
            out.message = e.getSafeMessage();
        } catch (Exception e) {
            out.errorCode = HybridIntegerationIntegrationException.UNEXPECTED;
            out.message = 'An unexpected error occurred.';
            System.debug(LoggingLevel.ERROR, 'getLatestReading failed: ' + e.getTypeName() + ': ' + e.getMessage());
        }
        return out;
    }

    private static AirQualityApiResponse execute(Id locationId, Boolean saveReading) {
        AirQualityApiResponse out = new AirQualityApiResponse();
        out.locationId = locationId;

        HybridIntegerationWeatherService.CallContext ctx = new HybridIntegerationWeatherService.CallContext();
        ctx.correlationId = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        out.correlationId = ctx.correlationId;

        String internalError = null;
        try {
            // 1) query + callout (no DML yet)
            HybridIntegerationAirQualityService.AirQualityResult result = HybridIntegerationAirQualityService.fetchForLocation(locationId, ctx);
            out.latitude = result.airQuality.latitude;
            out.longitude = result.airQuality.longitude;
            out.timezone = result.airQuality.timezone;

            // pure mapping (no DML); the response is populated from the mapped record so rounding is consistent
            Air_Quality_Reading__c reading = HybridIntegerationAirQualityMapper.toReading(result.airQuality, result.locationId);
            populateMeasurements(out, reading);

            // 2) DML
            if (saveReading) {
                out.readingId = HybridIntegerationAirQualityRepository.save(reading);
                out.saved = true;
            }
            out.success = true;
            out.message = saveReading ? 'Air quality reading saved.' : 'Air quality retrieved.';
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

        // 3) log (DML) after the callout; the logger never throws
        HybridIntegerationIntegrationLogger.LogEntry entry =
            new HybridIntegerationIntegrationLogger.LogEntry(HybridIntegerationIntegrationLogger.OPEN_METEO_AIR_QUALITY);
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

    private static void populateMeasurements(AirQualityApiResponse out, Air_Quality_Reading__c r) {
        out.recordedAt = r.Recorded_At__c;
        out.pm25 = r.PM25__c;
        out.pm10 = r.PM10__c;
        out.usAqi = r.US_AQI__c == null ? null : r.US_AQI__c.intValue();
        out.europeanAqi = r.European_AQI__c == null ? null : r.European_AQI__c.intValue();
        out.ozone = r.Ozone__c;
        out.nitrogenDioxide = r.Nitrogen_Dioxide__c;
    }
}
