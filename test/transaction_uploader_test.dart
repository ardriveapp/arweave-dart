import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/signer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures/test_wallet.dart';
import 'utils.dart' show generateByteList;

void main() {
  group('TransactionUploader POST /tx body', () {
    test('chunked upload sends transaction JSON with data key set to empty string',
        () async {
      String? capturedTxBody;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          if (request.url.path.endsWith('tx_anchor')) {
            return http.Response('dGVzdC1hbmNob3I', 200); // valid base64
          }
          if (request.url.path.contains('price/')) {
            return http.Response('1000000', 200);
          }
        }
        if (request.method == 'POST') {
          if (request.url.path.endsWith('tx')) {
            capturedTxBody = request.body;
            return http.Response('', 200);
          }
          if (request.url.path.endsWith('chunk')) {
            return http.Response('', 200);
          }
        }
        return http.Response('', 404);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse('https://arweave.net'),
        client: mockClient,
      );
      final client = Arweave(api: api);
      final wallet = getTestWallet();
      final signer = ArweaveSigner(wallet);

      // Data larger than 256KB so we get 2+ chunks (chunked path).
      final largeData = generateByteList(1); // 1 MB
      final transaction = await client.transactions.prepare(
        Transaction.withBlobData(data: largeData, reward: BigInt.one),
        wallet,
      );
      await transaction.sign(signer);

      expect(transaction.chunks!.chunks.length, greaterThan(1),
          reason: 'Need multiple chunks to exercise chunked upload path');

      final uploader = await client.transactions.getUploader(transaction);
      final events = uploader.upload().take(1);
      await for (final _ in events) {
        break; // Consume first event (after header is posted).
      }

      expect(capturedTxBody, isNotNull, reason: 'POST /tx body should be captured');
      final txJson = json.decode(capturedTxBody!) as Map<String, dynamic>;
      expect(txJson, contains('data'), reason: 'Node expects data key in JSON');
      expect(txJson['data'], equals(''),
          reason: 'Chunked upload must send empty data; payload goes via /chunk');
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('single-chunk upload sends transaction JSON with data key set to base64 payload',
        () async {
      String? capturedTxBody;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          if (request.url.path.endsWith('tx_anchor')) {
            return http.Response('dGVzdC1hbmNob3I', 200); // valid base64
          }
          if (request.url.path.contains('price/')) {
            return http.Response('1000000', 200);
          }
        }
        if (request.method == 'POST' && request.url.path.endsWith('tx')) {
          capturedTxBody = request.body;
          return http.Response('', 200);
        }
        return http.Response('', 404);
      });

      final api = ArweaveApi(
        gatewayUrl: Uri.parse('https://arweave.net'),
        client: mockClient,
      );
      final client = Arweave(api: api);
      final wallet = getTestWallet();
      final signer = ArweaveSigner(wallet);

      final smallData = Uint8List.fromList(utf8.encode('hello'));
      final transaction = await client.transactions.prepare(
        Transaction.withBlobData(data: smallData, reward: BigInt.one),
        wallet,
      );
      await transaction.sign(signer);

      expect(transaction.chunks!.chunks.length, equals(1),
          reason: 'Single chunk so data is sent in POST /tx body');

      await client.transactions.upload(transaction).drain();

      expect(capturedTxBody, isNotNull);
      final txJson = json.decode(capturedTxBody!) as Map<String, dynamic>;
      expect(txJson, contains('data'));
      expect(txJson['data'], isA<String>(), reason: 'data must be base64 string');
      expect((txJson['data'] as String).length, greaterThan(0),
          reason: 'Single-chunk upload must send base64 data in body');
    }, onPlatform: {'browser': Skip('dart:io only')});
  });
}
