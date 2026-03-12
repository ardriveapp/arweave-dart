import 'package:arweave/src/api/sandbox.dart';
import 'package:http/http.dart' as http;

import 'gateway_common.dart' if (dart.library.html) 'gateway_web.dart';

class ArweaveApi {
  final Uri gatewayUrl;

  final http.Client _client;

  ArweaveApi({
    Uri? gatewayUrl,
    http.Client? client,
  })  : gatewayUrl = gatewayUrl ?? getDefaultGateway(),
        _client = client ?? http.Client();

  Future<http.Response> get(String endpoint) =>
      _client.get(_getEndpointUri(endpoint));

  Future<http.Response> getSandboxedTx(String txId) =>
      _client.get(_getSandboxedEndpointUri(txId));

  Future<http.Response> post(String endpoint, {dynamic body}) {
    final uri = _getEndpointUri(endpoint);
    if (body == null) {
      return _client.post(uri);
    }
    return _client.post(
      uri,
      body: body,
      headers: {'Content-Type': 'application/json'},
    );
  }

  Uri _getEndpointUri(String endpoint) =>
      Uri.parse('${gatewayUrl.origin}/$endpoint');

  Uri _getSandboxedEndpointUri(String txId) => Uri.parse(
        '${gatewayUrl.scheme}://${getSandboxSubdomain(txId)}.${gatewayUrl.host}:${gatewayUrl.port}/$txId',
      );
}
