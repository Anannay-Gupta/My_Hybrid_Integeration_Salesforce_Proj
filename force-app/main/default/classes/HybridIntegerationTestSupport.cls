/** Shared test helpers: mock, JSON builder, location test data. */
@IsTest
public class HybridIntegerationTestSupport {
    public static HttpRequest lastRequest;
    public static Integer callCount = 0;

    public static final String LOC_VALID = 'TS Valid';
    public static final String LOC_NULL = 'TS Null Coordinates';
    public static final String LOC_BAD_LAT = 'TS Bad Latitude';
    public static final String LOC_BAD_LON = 'TS Bad Longitude';

    public static void reset() {
        lastRequest = null;
        callCount = 0;
    }

    public static String weatherJson(String localTime, Integer utcOffsetSeconds) {
        return '{"latitude":51.5,"longitude":-0.12,"utc_offset_seconds":' + utcOffsetSeconds
            + ',"timezone":"Europe/London","timezone_abbreviation":"GMT"'
            + ',"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"C"}'
            + ',"current":{"time":"' + localTime + '","interval":900,"temperature_2m":12.345,'
            + '"relative_humidity_2m":81,"precipitation":0.0,"wind_speed_10m":14.7}}';
    }

    public static String okJson() {
        return weatherJson('2026-11-12T14:30', 0);
    }

    public static String airQualityJson(String localTime, Integer utcOffsetSeconds) {
        return '{"latitude":51.5,"longitude":-0.12,"utc_offset_seconds":' + utcOffsetSeconds
            + ',"timezone":"Europe/London","timezone_abbreviation":"GMT"'
            + ',"current_units":{"time":"iso8601","interval":"seconds","pm10":"ug/m3","pm2_5":"ug/m3","us_aqi":"USAQI","european_aqi":"EAQI"}'
            + ',"current":{"time":"' + localTime + '","interval":3600,"pm10":20.456,"pm2_5":10.123,'
            + '"ozone":55.5,"nitrogen_dioxide":18.0,"us_aqi":42,"european_aqi":35}}';
    }

    public static String okAirQualityJson() {
        return airQualityJson('2026-11-12T14:30', 0);
    }

    /** Call from @TestSetup so DML is committed before any mock callout. */
    public static void createLocations() {
        insert new List<Location_Profile__c>{
            new Location_Profile__c(Name = LOC_VALID, City__c = 'London', Country__c = 'United Kingdom',
                Country_Code__c = 'GB', Latitude__c = 51.5074, Longitude__c = -0.1278),
            new Location_Profile__c(Name = LOC_NULL, City__c = 'Nowhere', Country__c = 'Nowhere'),
            new Location_Profile__c(Name = LOC_BAD_LAT, City__c = 'Bad', Country__c = 'Bad',
                Latitude__c = 91.5, Longitude__c = 10),
            new Location_Profile__c(Name = LOC_BAD_LON, City__c = 'Bad', Country__c = 'Bad',
                Latitude__c = 10, Longitude__c = 181.25)
        };
    }

    public static Id locationId(String name) {
        return [SELECT Id FROM Location_Profile__c WHERE Name = :name LIMIT 1].Id;
    }

    /** Well-formed 15-char Location_Profile__c Id that does not exist. */
    public static Id missingLocationId() {
        return Id.valueOf(Location_Profile__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    public class Mock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private String exceptionMessage;

        public Mock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public Mock(String exceptionMessage) {
            this.exceptionMessage = exceptionMessage;
        }

        public HttpResponse respond(HttpRequest req) {
            lastRequest = req;
            callCount++;
            if (exceptionMessage != null) {
                CalloutException ce = new CalloutException();
                ce.setMessage(exceptionMessage);
                throw ce;
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(body == null ? '' : body);
            return res;
        }
    }
}
