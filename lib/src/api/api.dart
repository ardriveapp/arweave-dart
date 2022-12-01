import 'package:ardrive_network/ardrive_network.dart';
import 'package:arweave/src/api/sandbox.dart';
import 'package:http/http.dart' as http;

import 'gateway_common.dart' if (dart.library.html) 'gateway_web.dart';

class ArweaveApi {
  final Uri gatewayUrl;

  final http.Client _client;

  final ardriveNetwork = ArdriveNetwork();

  ArweaveApi({
    Uri? gatewayUrl,
  })  : gatewayUrl = gatewayUrl ?? getDefaultGateway(),
        _client = http.Client();

  Future<ArDriveNetworkResponse> get(String endpoint) =>
      ardriveNetwork.get(url: _getEndpointUrl(endpoint));

  Future<ArDriveNetworkResponse> getJson(String endpoint) =>
      ardriveNetwork.getJson(_getEndpointUrl(endpoint));

  Future<ArDriveNetworkResponse> getSandboxedTx(String txId) =>
      ardriveNetwork.get(url: _getSandboxedEndpointUrl(txId));

  Future<ArDriveNetworkResponse> getSandboxedTxJson(String txId) =>
      ardriveNetwork.getJson(_getSandboxedEndpointUrl(txId));

  Future<http.Response> post(String endpoint, {dynamic body}) =>
      _client.post(_getEndpointUri(endpoint), body: body);

  String _getEndpointUrl(String endpoint) => '${gatewayUrl.origin}/$endpoint';

  String _getSandboxedEndpointUrl(String txId) =>
      '${gatewayUrl.scheme}://${getSandboxSubdomain(txId)}.${gatewayUrl.host}/$txId';

  Uri _getEndpointUri(String endpoint) =>
      Uri.parse('${gatewayUrl.origin}/$endpoint');
}
