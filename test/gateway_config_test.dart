import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures/test_wallet.dart';

void main() {
  const customGatewayOrigin = 'https://custom-gateway.example.com';

  group('gateway configuration', () {
    test('getTxAnchor uses configured api gateway URL', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('fake-anchor-base64', 200);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse(customGatewayOrigin),
        client: mockClient,
      );
      final result = await getTxAnchor(null, api: api).run();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.origin, equals(customGatewayOrigin));
      expect(capturedUri!.path.endsWith('tx_anchor'), isTrue);
      result.fold(
        (l) => fail('Expected right, got left: $l'),
        (r) => expect(r, equals('fake-anchor-base64')),
      );
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('getTxAnchor with explicit anchor does not call api', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response('', 200);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse(customGatewayOrigin),
        client: mockClient,
      );
      final result = await getTxAnchor('provided-anchor', api: api).run();

      expect(requestCount, equals(0));
      result.fold(
        (l) => fail('Expected right, got left: $l'),
        (r) => expect(r, equals('provided-anchor')),
      );
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('getTxPrice uses configured api gateway URL', () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('1000000', 200);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse(customGatewayOrigin),
        client: mockClient,
      );
      final result = await getTxPrice(null, 256, null, api: api).run();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.origin, equals(customGatewayOrigin));
      expect(capturedUri!.path.endsWith('price/256'), isTrue);
      result.fold(
        (l) => fail('Expected right, got left: $l'),
        (r) => expect(r, equals(BigInt.from(1000000))),
      );
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('getTxPrice with target uses configured api and correct path',
        () async {
      Uri? capturedUri;
      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        return http.Response('2000000', 200);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse(customGatewayOrigin),
        client: mockClient,
      );
      const target = 'GRQ7swQO1AMyFgnuAPI7AvGQlW3lzuQuwlJbIpWV7xk';
      final result = await getTxPrice(null, 512, target, api: api).run();

      expect(capturedUri, isNotNull);
      expect(capturedUri!.origin, equals(customGatewayOrigin));
      expect(capturedUri!.path.endsWith('price/512/$target'), isTrue);
      result.fold(
        (l) => fail('Expected right, got left: $l'),
        (r) => expect(r, equals(BigInt.from(2000000))),
      );
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('createTransactionTaskEither uses configured arweave gateway',
        () async {
      final requestedPaths = <String>[];
      final mockClient = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path.endsWith('tx_anchor')) {
          // Anchor is 32 bytes, return valid base64
          return http.Response(
            base64Url.encode(List.filled(32, 0)),
            200,
          );
        }
        if (request.url.path.contains('price/')) {
          return http.Response('1000000', 200);
        }
        return http.Response('', 404);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse(customGatewayOrigin),
        client: mockClient,
      );
      final arweave = Arweave(api: api);
      final wallet = getTestWallet();
      final dataStream =
          () => Stream.fromIterable([Uint8List.fromList(List.filled(100, 0))]);

      final result = await createTransactionTaskEither(
        wallet: wallet,
        dataStreamGenerator: dataStream,
        dataSize: 100,
        arweave: arweave,
      ).run();

      expect(
        requestedPaths,
        containsAll(['/tx_anchor', '/price/100']),
      );
      expect(
        requestedPaths
            .every((p) => p == '/tx_anchor' || p.startsWith('/price/')),
        isTrue,
      );
      result.fold(
        (l) => fail('Expected right, got left: $l'),
        (r) => expect(r.id, isNotEmpty),
      );
    }, onPlatform: {'browser': Skip('dart:io only')});
  });
}
