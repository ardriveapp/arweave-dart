import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'gateway_common.dart' if (dart.library.html) 'gateway_web.dart';

class ArweaveApi {
  final Uri gatewayUrl;

  final http.Client _client;

  ArweaveApi({
    Uri? gatewayUrl,
  })  : gatewayUrl = gatewayUrl ?? getDefaultGateway(),
        _client = http.Client();

  Future<http.Response> get(String endpoint) => retry<http.Response>(
        () => _client.get(_getEndpointUri(endpoint)),
        maxAttempts: 80,
      );

  Future<http.Response> post(String endpoint, {dynamic body}) async {
    return await retry<http.Response>(
      () => _client.post(_getEndpointUri(endpoint), body: body),
      maxAttempts: 80,
    );
  }

  Uri _getEndpointUri(String endpoint) =>
      Uri.parse('${gatewayUrl.origin}/$endpoint');
}
