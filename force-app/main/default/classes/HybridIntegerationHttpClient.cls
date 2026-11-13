/**
 * Generic, provider-agnostic HTTP callout utility.
 * No weather parsing, no DML. Header values are never logged.
 */
public with sharing class HybridIntegerationHttpClient {
    public static final Integer DEFAULT_TIMEOUT_MS = 10000;
    public static final Integer MAX_TIMEOUT_MS = 120000;

    public static HttpResponse send(String endpoint, String method, Map<String, String> headers, Integer timeoutMs) {
        if (String.isBlank(endpoint)) {
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.CALLOUT_FAILED,
                'Callout endpoint is blank.',
                'The request could not be sent.'
            );
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(String.isBlank(method) ? 'GET' : method.toUpperCase());

        Integer effectiveTimeout = (timeoutMs == null || timeoutMs <= 0) ? DEFAULT_TIMEOUT_MS : Math.min(timeoutMs, MAX_TIMEOUT_MS);
        req.setTimeout(effectiveTimeout);

        if (headers != null) {
            for (String name : headers.keySet()) {
                req.setHeader(name, headers.get(name));
            }
        }

        try {
            return new Http().send(req);
        } catch (CalloutException e) {
            String msg = e.getMessage() == null ? '' : e.getMessage();
            if (msg.containsIgnoreCase('timed out') || msg.containsIgnoreCase('timeout')) {
                throw new HybridIntegerationIntegrationException(
                    HybridIntegerationIntegrationException.TIMEOUT,
                    'Callout timed out after ' + effectiveTimeout + ' ms: ' + msg,
                    'The service took too long to respond. Please try again.'
                );
            }
            throw new HybridIntegerationIntegrationException(
                HybridIntegerationIntegrationException.CALLOUT_FAILED,
                'Callout failed: ' + msg,
                'The service could not be reached. Please try again later.'
            );
        }
    }
}
