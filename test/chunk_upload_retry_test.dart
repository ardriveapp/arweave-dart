@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/utils.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'fixtures/test_wallet.dart';

/// What an AR.IO gateway answers to POST /chunk when every peer rejected the
/// chunk, typically because the transaction header has not reached them yet.
const _gatewayBroadcastFailure = {
  'successCount': 0,
  'preferredSuccessCount': 0,
  'failureCount': 2,
  'results': [
    {'peer': 'http://a:1984', 'success': false, 'statusCode': 400},
    {'peer': 'http://b:1984', 'success': false, 'statusCode': 400},
  ],
};

Response<dynamic> _response(dynamic data, {String? contentType}) => Response(
      requestOptions: RequestOptions(path: '/chunk'),
      statusCode: 400,
      data: data,
      headers: Headers.fromMap({
        if (contentType != null) Headers.contentTypeHeader: [contentType],
      }),
    );

void main() {
  group('getResponseErrorFromDioRespose', () {
    test('returns a node error from a body Dio already decoded', () {
      expect(
        getResponseErrorFromDioRespose(
          _response({'error': 'data_root_not_found'},
              contentType: 'application/json'),
        ),
        'data_root_not_found',
      );
    });

    test('returns the legacy nested error', () {
      expect(
        getResponseErrorFromDioRespose(_response({
          'data': {'error': 'invalid_proof'}
        })),
        'invalid_proof',
      );
    });

    test('returns a node error from an undecoded JSON string', () {
      expect(
        getResponseErrorFromDioRespose(
          _response('{"error":"chunk_too_big"}'),
        ),
        'chunk_too_big',
      );
    });

    test('returns a gateway broadcast result whole, without throwing', () {
      final error = getResponseErrorFromDioRespose(
        _response(_gatewayBroadcastFailure,
            contentType: 'application/json; charset=utf-8'),
      );
      expect(json.decode(error), _gatewayBroadcastFailure);
    });

    test('returns plain text and empty bodies as they are', () {
      expect(getResponseErrorFromDioRespose(_response('Bad Request')),
          'Bad Request');
      expect(getResponseErrorFromDioRespose(_response(null)), '');
    });
  });

  group('uploadTransaction', () {
    late HttpServer server;
    late List<int> chunkStatuses;
    late int headerPosts;

    setUp(() async {
      chunkStatuses = [];
      headerPosts = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() => server.close(force: true));

    /// Serves the endpoints an upload touches, answering each POST /chunk
    /// with the next status in [chunkAnswers] (200 once they run out).
    void serve(List<int> chunkAnswers) {
      server.listen((request) async {
        final path = request.uri.path;
        final response = request.response;
        await request.drain<void>();
        if (path == '/tx_anchor') {
          response.write('dGVzdC1hbmNob3I');
        } else if (path.startsWith('/price/')) {
          response.write('1000000');
        } else if (path == '/tx') {
          headerPosts++;
          response.write('OK');
        } else if (path == '/chunk') {
          final status = chunkStatuses.length < chunkAnswers.length
              ? chunkAnswers[chunkStatuses.length]
              : 200;
          chunkStatuses.add(status);
          response.statusCode = status;
          if (status != 200) {
            response.headers.contentType = ContentType.json;
            response.write(json.encode(_gatewayBroadcastFailure));
          }
        } else {
          response.statusCode = 404;
        }
        await response.close();
      });
    }

    Future<TransactionResult> singleChunkTransaction(Arweave arweave) async {
      final data = Uint8List.fromList(List.generate(10 * 1024, (i) => i % 256));
      final result = await createTransactionTaskEither(
        wallet: getTestWallet(),
        dataStreamGenerator: () => Stream.value(data),
        dataSize: data.length,
        arweave: arweave,
      ).run();
      return result.getOrElse((error) => throw error);
    }

    test(
        'retries a chunk the gateway rejected with a JSON body '
        '(header not yet propagated) instead of failing the upload', () async {
      serve([400]);
      final arweave = Arweave(
        api: ArweaveApi(
          gatewayUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
      );
      final transaction = await singleChunkTransaction(arweave);

      final started = await uploadTransaction(transaction, arweave).run();
      final (progress, _) = started.getOrElse((error) => throw error);
      final events = await progress.toList();

      expect(headerPosts, 1);
      expect(chunkStatuses, [400, 200]);
      expect(events.last, (1, 1));
    });

    test('uploadTransactionChunks posts the chunks and not the header',
        () async {
      serve([]);
      final arweave = Arweave(
        api: ArweaveApi(
          gatewayUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
      );
      final transaction = await singleChunkTransaction(arweave);

      final started = await uploadTransactionChunks(transaction, arweave).run();
      final (progress, _) = started.getOrElse((error) => throw error);
      final events = await progress.toList();

      expect(headerPosts, 0);
      expect(chunkStatuses, [200]);
      expect(events.last, (1, 1));
    });
  });
}
