
// ============================================
// HARMONY - PHASE 2 API SMOKE TEST
// ============================================

// TEST 1: WEATHER API

HttpRequest weatherReq = new HttpRequest();

weatherReq.setEndpoint(
    'callout:Hybrid_Integeration_Weather/v1/forecast' +
    '?latitude=28.6139' +
    '&longitude=77.2090' +
    '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation' +
    '&timezone=auto'
);

weatherReq.setMethod('GET');
weatherReq.setHeader('Accept', 'application/json');
weatherReq.setTimeout(20000);

Http weatherHttp = new Http();

HttpResponse weatherRes = weatherHttp.send(weatherReq);

System.debug('===== WEATHER API =====');
System.debug('Status: ' + weatherRes.getStatusCode());
System.debug('Response: ' + weatherRes.getBody());


// TEST 2: AIR QUALITY API

HttpRequest airReq = new HttpRequest();

airReq.setEndpoint(
    'callout:Hybrid_Integeration_Air_Quality/v1/air-quality' +
    '?latitude=28.6139' +
    '&longitude=77.2090' +
    '&current=pm10,pm2_5,us_aqi,european_aqi,ozone,nitrogen_dioxide' +
    '&timezone=auto'
);

airReq.setMethod('GET');
airReq.setHeader('Accept', 'application/json');
airReq.setTimeout(20000);

Http airHttp = new Http();

HttpResponse airRes = airHttp.send(airReq);

System.debug('===== AIR QUALITY API =====');
System.debug('Status: ' + airRes.getStatusCode());
System.debug('Response: ' + airRes.getBody());


// TEST 3: API Ninjas Holiday API


HttpRequest req = new HttpRequest();

req.setEndpoint(
    'callout:Hybrid_Integration_Holidays/v1/publicholidays?country=IN'
);

req.setMethod('GET');
req.setHeader('Accept', 'application/json');
req.setTimeout(20000);

try {
    HttpResponse res = new Http().send(req);

    System.debug('===== API NINJAS HOLIDAYS =====');
    System.debug('STATUS: ' + res.getStatusCode());
    System.debug('RESPONSE: ' + res.getBody());

    if (res.getStatusCode() == 200) {
        List<Object> holidays =
            (List<Object>) JSON.deserializeUntyped(res.getBody());

        System.debug('TOTAL HOLIDAYS: ' + holidays.size());
    }

} catch (Exception e) {
    System.debug('ERROR: ' + e.getMessage());
}
