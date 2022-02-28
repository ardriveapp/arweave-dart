import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'gateway_common.dart' if (dart.library.html) 'gateway_web.dart';

const MAX_POST_RETRY = 10;

class ArweaveApi {
  final Uri gatewayUrl;

  final http.Client _client;

  ArweaveApi({
    Uri? gatewayUrl,
  })  : gatewayUrl = gatewayUrl ?? getDefaultGateway(),
        _client = http.Client();

  Future<http.Response> get(String endpoint) =>
      _client.get(_getEndpointUri(endpoint));

  Future<http.Response> post(String endpoint, {dynamic body}) async {
    return await retry<http.Response>(
      () => _client.post(_getEndpointUri(endpoint), body: body),
      maxAttempts: MAX_POST_RETRY,
    );
  }

  Uri _getEndpointUri(String endpoint) =>
      Uri.parse('${gatewayUrl.origin}/$endpoint');
}
