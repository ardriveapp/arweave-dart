import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:async/async.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart';
import 'package:mutex/mutex.dart';
import 'package:retry/retry.dart';

import '../api/api.dart';
import '../crypto/crypto.dart';
import '../utils.dart';
import 'errors.dart';

/// Errors from /chunk we should never try and continue on.
const _fatalChunkUploadErrors = [
  'invalid_json',
  'chunk_too_big',
  'data_path_too_big',
  'offset_too_big',
  'data_size_too_big',
  'chunk_proof_ratio_not_attractive',
  'invalid_proof'
];

TaskEither<StreamTransactionError, Stream<(int, int)>> uploadTransaction(
    TransactionResult transaction) {
  final arweave = ArweaveApi();
  final txHeaders = transaction.toJson();

  return _postTransactionHeaderTaskEither(arweave, txHeaders).flatMap((_) {
    print('call post chunks');
    return TaskEither.of(_postChunks(arweave, transaction));
  });
}

TaskEither<StreamTransactionError, Response> _postTransactionHeaderTaskEither(
    ArweaveApi arweave, Map<String, dynamic> headers) {
  return TaskEither.tryCatch(() async {
    print('Uploading transaction headers...');

    final res = await arweave.post('tx', body: json.encode(headers));

    if (!(res.statusCode >= 200 && res.statusCode < 300)) {
      print('Unable to upload transaction: ${res.statusCode}');
      throw Exception('Unable to upload transaction: ${res.statusCode}');
    }

    return res;
  }, (error, _) => PostTxHeadersError());
}

Stream<(int, int)> _postChunks(
  ArweaveApi arweave,
  TransactionResult transaction,
) async* {
  print('Uploading chunks...');
  final chunkUploadCompletionStreamController = StreamController<int>();
  final chunkStream = transaction.chunkStreamGenerator();
  final chunkQueue = StreamQueue(chunkStream);
  final totalChunks = transaction.chunks.chunks.length;

  final maxConcurrentChunkUploadCount = 128;
  int chunkIndex = 0;
  int uploadedChunks = 0;
  isComplete() => uploadedChunks >= totalChunks;

  Future<void> uploadChunkAndNotifyOfCompletion(
      int chunkIndex, TransactionChunk chunk) async {
    try {
      await retry(
        () => _uploadChunk(
          arweave,
          chunkIndex,
          chunk,
          transaction.chunks.dataRoot,
        ),
        onRetry: (exception) {
          print(
            'Retrying for chunk $chunkIndex on exception ${exception.toString()}',
          );
        },
      );

      print('chunk uploaded');

      chunkUploadCompletionStreamController.add(chunkIndex);
    } catch (err) {
      print('Chunk upload failed at $chunkIndex');
      chunkUploadCompletionStreamController.addError(err);
    }
  }

  final mutex = Mutex();

  // Initiate as many chunk uploads as we can in parallel at the start.
  // Note that onListen is not actually awaited, so should be protected by Mutex
  // to ensure that additional chunk uploads are not started before these.
  chunkUploadCompletionStreamController.onListen = () async {
    await mutex.protect(() async {
      while (chunkIndex < totalChunks &&
          chunkIndex < maxConcurrentChunkUploadCount) {
        uploadChunkAndNotifyOfCompletion(chunkIndex, await chunkQueue.next);
        chunkIndex++;
      }
    });
  };

  // Start a new chunk upload if there are still any left to upload and
  // notify the stream consumer of chunk upload completion events.
  yield* chunkUploadCompletionStreamController.stream
      .map((completedChunkIndex) {
    uploadedChunks++;

    // chunkIndex and chunkQueue must be protected from race conditions by Mutex
    // Note that the future is not awaited, so it will be queued after returning
    mutex.protect(() async {
      if (chunkIndex < totalChunks) {
        uploadChunkAndNotifyOfCompletion(chunkIndex, await chunkQueue.next);
        chunkIndex++;
      } else if (isComplete()) {
        if (await chunkQueue.hasNext) {
          throw StateError('Chunks remaining in queue');
        }
        chunkQueue.cancel();
        chunkUploadCompletionStreamController.close();
      }
    });

    return (uploadedChunks, totalChunks);
  });
}

Future<void> _uploadChunk(ArweaveApi arweave, int chunkIndex,
    TransactionChunk chunk, Uint8List dataRoot) async {
  final chunkValid = await validatePath(
    dataRoot,
    int.parse(chunk.offset),
    0,
    int.parse(chunk.dataSize),
    decodeBase64ToBytes(chunk.dataPath),
  );

  if (!chunkValid) {
    throw StateError('Unable to validate chunk: $chunkIndex');
  }

  final res = await arweave.post('chunk', body: json.encode(chunk));
  print('Uploaded chunk $chunkIndex: ${res.statusCode}');

  if (res.statusCode != 200) {
    final responseError = getResponseError(res);

    if (_fatalChunkUploadErrors.contains(responseError)) {
      throw StateError(
          'Fatal error uploading chunk: $chunkIndex: ${res.statusCode} $responseError');
    } else {
      throw Exception(
          'Received non-fatal error while uploading chunk $chunkIndex: ${res.statusCode} $responseError');
    }
  }
}
