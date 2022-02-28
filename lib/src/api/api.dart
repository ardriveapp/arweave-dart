import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'gateway_common.dart' if (dart.library.html) 'gateway_web.dart';

const MAX_RETRIES = 10;

class ArweaveApi {
  final Uri gatewayUrl;

  final http.Client _client;

  ArweaveApi({
    Uri? gatewayUrl,
  })  : gatewayUrl = gatewayUrl ?? getDefaultGateway(),
        _client = http.Client();

  Future<http.Response> get(String endpoint, {int maxRetries = MAX_RETRIES}) =>
      retry<http.Response>(
        () => _client.get(_getEndpointUri(endpoint)),
        maxAttempts: maxRetries,
      );

  Future<http.Response> post(
    String endpoint, {
    dynamic body,
    int maxRetries = MAX_RETRIES,
  }) async {
    return await retry<http.Response>(
      () => _client.post(_getEndpointUri(endpoint), body: body),
      maxAttempts: maxRetries,
    );
  }

  Uri _getEndpointUri(String endpoint) =>
      Uri.parse('${gatewayUrl.origin}/$endpoint');
}
