import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/signer.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures/test_wallet.dart';
import 'utils.dart' show generateByteList;

/// Chunk POSTs may send `application/json` or e.g. `application/json; charset=utf-8`.
bool _contentTypeStartsWithApplicationJson(String? header) =>
    header != null &&
    header.toLowerCase().trim().startsWith('application/json');

void main() {
  group('TransactionUploader POST /tx body', () {
    test('chunked upload sends transaction JSON with data key set to empty string',
        () async {
      String? capturedTxBody;
      http.Request? capturedTxRequest;
      http.Request? capturedChunkRequest;
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
            capturedTxRequest = request;
            capturedTxBody = request.body;
            return http.Response('', 200);
          }
          if (request.url.path.endsWith('chunk')) {
            capturedChunkRequest ??= request;
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
      // First event: header posted; second: at least one chunk completed (POST /chunk).
      await uploader.upload().take(2).toList();

      expect(capturedTxBody, isNotNull, reason: 'POST /tx body should be captured');
      expect(capturedTxRequest, isNotNull);
      expect(
          capturedTxRequest!.headers['content-type'],
          equals('application/json'),
          reason: 'POST /tx must send Content-Type: application/json');
      expect(capturedChunkRequest, isNotNull,
          reason: 'At least one POST /chunk should occur');
      expect(
          _contentTypeStartsWithApplicationJson(
              capturedChunkRequest!.headers['content-type']),
          isTrue,
          reason:
              'POST /chunk must send Content-Type starting with application/json');
      final txJson = json.decode(capturedTxBody!) as Map<String, dynamic>;
      expect(txJson, contains('data'), reason: 'Node expects data key in JSON');
      expect(txJson['data'], equals(''),
          reason: 'Chunked upload must send empty data; payload goes via /chunk');
    }, onPlatform: {'browser': Skip('dart:io only')});

    test('single-chunk upload sends transaction JSON with data key set to base64 payload',
        () async {
      String? capturedTxBody;
      http.Request? capturedTxRequest;
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
          capturedTxRequest = request;
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
      expect(capturedTxRequest, isNotNull);
      expect(
          capturedTxRequest!.headers['content-type'],
          equals('application/json'),
          reason: 'POST /tx must send Content-Type: application/json');
      final txJson = json.decode(capturedTxBody!) as Map<String, dynamic>;
      expect(txJson, contains('data'));
      expect(txJson['data'], isA<String>(), reason: 'data must be base64 string');
      expect((txJson['data'] as String).length, greaterThan(0),
          reason: 'Single-chunk upload must send base64 data in body');
    }, onPlatform: {'browser': Skip('dart:io only')});
  });

  group('TransactionUploader chunk uploads', () {
    test('POST /chunk once per chunk with application/json and required fields',
        () async {
      final chunkBodies = <String>[];
      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          if (request.url.path.endsWith('tx_anchor')) {
            return http.Response('dGVzdC1hbmNob3I', 200);
          }
          if (request.url.path.contains('price/')) {
            return http.Response('1000000', 200);
          }
        }
        if (request.method == 'POST') {
          if (request.url.path.endsWith('tx')) {
            return http.Response('', 200);
          }
          if (request.url.path.endsWith('chunk')) {
            expect(
              _contentTypeStartsWithApplicationJson(
                  request.headers['content-type']),
              isTrue,
              reason:
                  'each chunk POST must use Content-Type starting with application/json',
            );
            chunkBodies.add(request.body);
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

      final largeData = generateByteList(1);
      final transaction = await client.transactions.prepare(
        Transaction.withBlobData(data: largeData, reward: BigInt.one),
        wallet,
      );
      await transaction.sign(signer);

      final totalChunks = transaction.chunks!.chunks.length;
      expect(totalChunks, greaterThan(1));

      await client.transactions.upload(transaction).drain();

      expect(
        chunkBodies.length,
        equals(totalChunks),
        reason: 'one POST /chunk per merkle chunk',
      );

      for (var i = 0; i < chunkBodies.length; i++) {
        final map = json.decode(chunkBodies[i]) as Map<String, dynamic>;
        expect(
          map.keys.toSet(),
          containsAll(['data_root', 'data_size', 'data_path', 'offset', 'chunk']),
          reason: 'chunk $i must include gateway chunk schema fields',
        );
        expect(map['data_root'], equals(transaction.dataRoot));
        expect((map['chunk'] as String).isNotEmpty, isTrue);
        expect((map['data_path'] as String).isNotEmpty, isTrue);
        expect(map['offset'], isA<String>());
        expect(map['data_size'], isA<String>());
      }
    }, onPlatform: {'browser': Skip('dart:io only')});
  });
}
