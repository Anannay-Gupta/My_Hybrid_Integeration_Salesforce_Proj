/**
 * Weather integration orchestration. Contains NO DML.
 * Callout-only: location query -> validation -> callout -> status check -> deserialize -> validate.
 * Failures are thrown as HybridIntegerationIntegrationException; call metadata (timings, status, endpoint)
 * is written into the caller-supplied CallContext so the caller can log it even when an exception is thrown.
 */
public with sharing class HybridIntegerationWeatherService {
    public static final String NAMED_CREDENTIAL = 'Hybrid_Integeration_Weather';
    public static final String FORECAST_PATH = '/v1/forecast';
    public static final String CURRENT_VARIABLES = 'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m';
    public static final Integer TIMEOUT_MS = 10000;

    public class CallContext {
        public String httpMethod = 'GET';
        public String endpoint;
        public String correlationId;
        public Datetime requestTime;
        public Datetime responseTime;
        public Long durationMs;
        public Integer statusCode;
        public String responseSummary;
    }

    public class WeatherResult {
        public Id locationId;
        public HybridIntegerationWeatherResponse weather;
        public CallContext context;
    }

    public static WeatherResult fetchForLocation(Id locationId) {
        return fetchForLocation(locationId, new CallContext());
    }

    public static WeatherResult fetchForLocation(Id locationId, CallContext ctx) {
        Location_Profile__c loc = getLocation(locationId);
        WeatherResult result = fetchForCoordinates(loc.Latitude__c, loc.Longitude__c, ctx);
        result.locationId = loc.Id;
        return result;
    }

    public static WeatherResult fetchForCoordinates(Decimal latitude, Decimal longitude) {
        return fetchForCoordinates(latitude, longitude, new CallContext());
    }

    public static WeatherResult fetchForCoordinates(Decimal latitude, Decimal longitude, CallContext ctx) {
        if (ctx == null) {
            ctx = new CallContext();
        }
        validateCoordinates(latitude, longitude);
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

        HybridIntegerationWeatherResponse weather = HybridIntegerationWeatherResponse.parse(body);
        if (!weather.hasCurrentData()) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.MISSING_CURRENT,
                'Open-Meteo response has no usable "current" block.',
                'The weather service returned no current weather data.',
                res.getStatusCode()
            );
        }

        ctx.responseSummary = 'time=' + weather.current.time_x
            + '; temperature_2m=' + weather.current.temperature_2m
            + '; relative_humidity_2m=' + weather.current.relative_humidity_2m
            + '; precipitation=' + weather.current.precipitation
            + '; wind_speed_10m=' + weather.current.wind_speed_10m
            + '; timezone=' + weather.timezone;

        WeatherResult result = new WeatherResult();
        result.weather = weather;
        result.context = ctx;
        return result;
    }

    public static Location_Profile__c getLocation(Id locationId) {
        if (locationId == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.LOCATION_NOT_FOUND,
                'Location_Profile__c Id was null.',
                'No location was selected.'
            );
        }
        List<Location_Profile__c> rows;
        try {
            rows = [
                SELECT Id, Latitude__c, Longitude__c
                FROM Location_Profile__c
                WHERE Id = :locationId
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.ACCESS_DENIED,
                'Location query failed (likely CRUD/FLS): ' + e.getMessage(),
                'You do not have access to this location.'
            );
        }
        if (rows.isEmpty()) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.LOCATION_NOT_FOUND,
                'No accessible Location_Profile__c found for Id ' + locationId,
                'The selected location could not be found.'
            );
        }
        return rows[0];
    }

    public static void validateCoordinates(Decimal latitude, Decimal longitude) {
        if (latitude == null || longitude == null) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.NULL_COORDINATES,
                'Latitude or longitude is null.',
                'This location has no coordinates.'
            );
        }
        if (latitude < -90 || latitude > 90) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.INVALID_COORDINATES,
                'Latitude ' + latitude + ' is outside -90..90.',
                'This location has an invalid latitude.'
            );
        }
        if (longitude < -180 || longitude > 180) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.INVALID_COORDINATES,
                'Longitude ' + longitude + ' is outside -180..180.',
                'This location has an invalid longitude.'
            );
        }
    }

    public static String buildEndpoint(Decimal latitude, Decimal longitude) {
        return 'callout:' + NAMED_CREDENTIAL + FORECAST_PATH
            + '?latitude=' + EncodingUtil.urlEncode(latitude.setScale(6).toPlainString(), 'UTF-8')
            + '&longitude=' + EncodingUtil.urlEncode(longitude.setScale(6).toPlainString(), 'UTF-8')
            + '&current=' + EncodingUtil.urlEncode(CURRENT_VARIABLES, 'UTF-8')
            + '&timezone=' + EncodingUtil.urlEncode('auto', 'UTF-8');
    }

    @TestVisible
    private static void validateStatus(Integer status, String body) {
        if (status == 200) {
            return;
        }
        String reason = extractReason(body);
        String detail = 'Open-Meteo returned HTTP ' + status + (reason == null ? '' : ': ' + reason);
        String code;
        String userMsg;
        if (status == 400) {
            code = HybridIntegerationIntegrationException.HTTP_BAD_REQUEST;
            userMsg = 'The weather request was rejected as invalid.';
        } else if (status == 401 || status == 403) {
            code = HybridIntegerationIntegrationException.HTTP_AUTH;
            userMsg = 'The weather service denied access. Please contact your administrator.';
        } else if (status == 429) {
            code = HybridIntegerationIntegrationException.HTTP_RATE_LIMIT;
            userMsg = 'The weather service is rate limiting requests. Please try again later.';
        } else if (status >= 500) {
            code = HybridIntegerationIntegrationException.HTTP_SERVER_ERROR;
            userMsg = 'The weather service is currently unavailable. Please try again later.';
        } else {
            code = HybridIntegerationIntegrationException.HTTP_UNEXPECTED;
            userMsg = 'The weather service returned an unexpected response.';
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

    private static void stamp(CallContext ctx, Long startMs) {
        ctx.responseTime = Datetime.now();
        ctx.durationMs = System.currentTimeMillis() - startMs;
    }

    private static String truncate(String s, Integer maxLen) {
        if (s == null || s.length() <= maxLen) {
            return s;
        }
        return s.substring(0, maxLen);
    }
}
