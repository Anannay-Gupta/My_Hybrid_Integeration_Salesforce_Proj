/**
 * Air Quality callout orchestration. Contains NO DML.
 * Reuses WeatherService.getLocation / validateCoordinates / CallContext and HttpClient.
 * Failures are thrown as IntegrationException; call metadata is written into the caller's CallContext.
 */
public with sharing class HybridIntegerationAirQualityService {
    public static final String NAMED_CREDENTIAL = 'Hybrid_Integeration_Air_Quality';
    public static final String AIR_QUALITY_PATH = '/v1/air-quality';
    public static final String CURRENT_VARIABLES = 'pm2_5,pm10,us_aqi,european_aqi,ozone,nitrogen_dioxide';
    public static final Integer TIMEOUT_MS = 10000;

    public class AirQualityResult {
        public Id locationId;
        public HybridIntegerationAirQualityResponse airQuality;
        public HybridIntegerationWeatherService.CallContext context;
    }

    public static AirQualityResult fetchForLocation(Id locationId) {
        return fetchForLocation(locationId, new HybridIntegerationWeatherService.CallContext());
    }

    public static AirQualityResult fetchForLocation(Id locationId, HybridIntegerationWeatherService.CallContext ctx) {
        Location_Profile__c loc = HybridIntegerationWeatherService.getLocation(locationId);
        AirQualityResult result = fetchForCoordinates(loc.Latitude__c, loc.Longitude__c, ctx);
        result.locationId = loc.Id;
        return result;
    }

    public static AirQualityResult fetchForCoordinates(Decimal latitude, Decimal longitude) {
        return fetchForCoordinates(latitude, longitude, new HybridIntegerationWeatherService.CallContext());
    }

    public static AirQualityResult fetchForCoordinates(Decimal latitude, Decimal longitude, HybridIntegerationWeatherService.CallContext ctx) {
        if (ctx == null) {
            ctx = new HybridIntegerationWeatherService.CallContext();
        }
        HybridIntegerationWeatherService.validateCoordinates(latitude, longitude);
        ctx.endpoint = buildEndpoint(latitude, longitude);

        Map<String, String> headers = new Map<String, String>{ 'Accept' => 'application/json' };
        ctx.requestTime = Datetime.now();
        Long startMs = System.currentTimeMillis();

        HttpResponse res;
        try {
            res = HybridIntegerationHttpClient.send(ctx.endpoint, ctx.httpMethod, headers, TIMEOUT_MS);
        } catch (HybridIntegerationIntegrationException e) {
            stamp(ctx, startMs);
            throw e;
        }
        stamp(ctx, startMs);

        ctx.statusCode = res.getStatusCode();
        String body = res.getBody();
        ctx.responseSummary = truncate(body, 500);

        validateStatus(res.getStatusCode(), body);

        HybridIntegerationAirQualityResponse airQuality = HybridIntegerationAirQualityResponse.parse(body);
        if (!airQuality.hasCurrentData()) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MISSING_CURRENT,
                'Open-Meteo Air Quality response has no usable "current" block.',
                'The air quality service returned no current measurements.',
                res.getStatusCode()
            );
        }

        ctx.responseSummary = 'time=' + airQuality.current.time_x
            + '; pm2_5=' + airQuality.current.pm2_5
            + '; pm10=' + airQuality.current.pm10
            + '; us_aqi=' + airQuality.current.us_aqi
            + '; european_aqi=' + airQuality.current.european_aqi
            + '; ozone=' + airQuality.current.ozone
            + '; nitrogen_dioxide=' + airQuality.current.nitrogen_dioxide
            + '; timezone=' + airQuality.timezone;

        AirQualityResult result = new AirQualityResult();
        result.airQuality = airQuality;
        result.context = ctx;
        return result;
    }

    public static String buildEndpoint(Decimal latitude, Decimal longitude) {
        return 'callout:' + NAMED_CREDENTIAL + AIR_QUALITY_PATH
            + '?latitude=' + EncodingUtil.urlEncode(latitude.setScale(6).toPlainString(), 'UTF-8')
            + '&longitude=' + EncodingUtil.urlEncode(longitude.setScale(6).toPlainString(), 'UTF-8')
            + '&current=' + EncodingUtil.urlEncode(CURRENT_VARIABLES, 'UTF-8')
            + '&timezone=' + EncodingUtil.urlEncode('auto', 'UTF-8');
    }

    // NOTE: mirrors WeatherService.validateStatus (private there). Candidate for extraction into a shared class.
    private static void validateStatus(Integer status, String body) {
        if (status == 200) {
            return;
        }
        String reason = extractReason(body);
        String detail = 'Open-Meteo Air Quality returned HTTP ' + status + (reason == null ? '' : ': ' + reason);
        String code;
        String userMsg;
        if (status == 400) {
            code = HybridIntegerationIntegrationException.HTTP_BAD_REQUEST;
            userMsg = 'The air quality request was rejected as invalid.';
        } else if (status == 401 || status == 403) {
            code = HybridIntegerationIntegrationException.HTTP_AUTH;
            userMsg = 'The air quality service denied access. Please contact your administrator.';
        } else if (status == 429) {
            code = HybridIntegerationIntegrationException.HTTP_RATE_LIMIT;
            userMsg = 'The air quality service is rate limiting requests. Please try again later.';
        } else if (status >= 500) {
            code = HybridIntegerationIntegrationException.HTTP_SERVER_ERROR;
            userMsg = 'The air quality service is currently unavailable. Please try again later.';
        } else {
            code = HybridIntegerationIntegrationException.HTTP_UNEXPECTED;
            userMsg = 'The air quality service returned an unexpected response.';
        }
        throw new HybridIntegerationIntegrationException(code, detail, userMsg, status);
    }

    private static String extractReason(String body) {
        if (String.isBlank(body)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof Map<String, Object>) {
                Object reason = ((Map<String, Object>) parsed).get('reason');
                return reason == null ? null : truncate(String.valueOf(reason), 300);
            }
        } catch (Exception e) {
            // body is not JSON; fall through
        }
        return null;
    }

    private static void stamp(HybridIntegerationWeatherService.CallContext ctx, Long startMs) {
        ctx.responseTime = Datetime.now();
        ctx.durationMs = System.currentTimeMillis() - startMs;
    }

    private static String truncate(String s, Integer maxLen) {
        return (s == null || s.length() <= maxLen) ? s : s.substring(0, maxLen);
    }
}
