import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:async/async.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
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

TaskEither<StreamTransactionError, (Stream<(int, int)>, UploadAborter)>
    uploadTransaction(TransactionResult transaction, [Arweave? arweaveClient]) {
  final arweave = arweaveClient?.api ?? ArweaveApi();
  final txHeaders = transaction.toJson();
  final aborter = UploadAborter();

  return _postTransactionHeaderTaskEither(arweave, txHeaders).flatMap((_) {
    return TaskEither.of((_postChunks(arweave, transaction, aborter), aborter));
  });
}

// TODO: Add Dio to the ArweaveAPI class and use that instead of creating a new
// instance here.
TaskEither<StreamTransactionError, Response> _postTransactionHeaderTaskEither(
    ArweaveApi arweave, Map<String, dynamic> headers) {
  return TaskEither.tryCatch(() async {
    final endpoint = '${arweave.gatewayUrl}/tx';
    final Dio dio = Dio();
    final res = await dio.post(endpoint, data: json.encode(headers));

    if (res.statusCode == null) {
      throw Exception('Unable to upload transaction: ${res.statusCode}');
    }

    if (!(res.statusCode! >= 200 && res.statusCode! < 300)) {
      throw Exception('Unable to upload transaction: ${res.statusCode}');
    }

    return res;
  }, (error, _) => PostTxHeadersError());
}

Stream<(int, int)> _postChunks(
  ArweaveApi arweave,
  TransactionResult transaction,
  UploadAborter aborter,
) async* {
  final chunkUploadCompletionStreamController = StreamController<int>();
  final chunkStream = transaction.chunkStreamGenerator();
  final chunkQueue = StreamQueue(chunkStream);

  if (aborter.aborted) {
    throw StateError('Upload aborted');
  }

  aborter.setChunkQueue(chunkQueue);

  final totalChunks = transaction.chunks.chunks.length;

  final maxConcurrentChunkUploadCount = 128;
  int chunkIndex = 0;
  int uploadedChunks = 0;
  isComplete() => uploadedChunks >= totalChunks;

  final mutex = Mutex();

  // Initiate as many chunk uploads as we can in parallel at the start.
  // Note that onListen is not actually awaited, so should be protected by Mutex
  // to ensure that additional chunk uploads are not started before these.
  chunkUploadCompletionStreamController.onListen = () async {
    await mutex.protect(() async {
      while (chunkIndex < totalChunks &&
          chunkIndex < maxConcurrentChunkUploadCount) {
        final chunkUploader =
            ChunkUploader(transaction, chunkUploadCompletionStreamController, arweave);

        aborter.addChunk(chunkUploader);

        chunkUploader
            .uploadChunkAndNotifyOfCompletion(chunkIndex, await chunkQueue.next)
            .then((value) {
          aborter.removeChunk(chunkUploader);
        });
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
        final chunkUploader =
            ChunkUploader(transaction, chunkUploadCompletionStreamController, arweave);
        aborter.addChunk(chunkUploader);

        chunkUploader
            .uploadChunkAndNotifyOfCompletion(chunkIndex, await chunkQueue.next)
            .then((value) {
          aborter.removeChunk(chunkUploader);
        });
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

class UploadAborter {
  StreamQueue<TransactionChunk>? chunkQueue;
  List<ChunkUploader> chunkUploaders = [];
  bool aborted = false;

  void setChunkQueue(StreamQueue<TransactionChunk> queue) {
    chunkQueue = queue;
  }

  void addChunk(ChunkUploader chunk) {
    chunkUploaders.add(chunk);
  }

  void removeChunk(ChunkUploader chunk) {
    chunkUploaders.remove(chunk);
  }

  Future<void> abort() async {
    for (var chunk in chunkUploaders) {
      chunk.cancel();
    }

    chunkQueue?.cancel(immediate: true);

    aborted = true;
  }
}

class ChunkUploader {
  final TransactionResult transaction;
  final StreamController<int> chunkUploadCompletionStreamController;
  final ArweaveApi arweave;
  final CancelToken _cancelToken = CancelToken();

  ChunkUploader(this.transaction, this.chunkUploadCompletionStreamController, this.arweave);

  Future<void> uploadChunkAndNotifyOfCompletion(
      int chunkIndex, TransactionChunk chunk) async {
    try {
      await retry(
        () => _uploadChunk(
          chunkIndex,
          chunk,
          transaction.chunks.dataRoot,
        ),
        onRetry: (exception) {
          if (exception is DioException) {
            if (exception.type == DioExceptionType.cancel) {
              throw exception;
            }
          }
          print(
            'Retrying for chunk $chunkIndex on exception ${exception.toString()}',
          );
        },
      );

      chunkUploadCompletionStreamController.add(chunkIndex);
    } catch (err) {
      chunkUploadCompletionStreamController.addError(err);
    }
  }

  Future<void> _uploadChunk(
    int chunkIndex,
    TransactionChunk chunk,
    Uint8List dataRoot,
  ) async {
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

    // TODO: Add Dio to the ArweaveAPI class and use that instead of creating a new
    // instance here.
    final dio = Dio();

    final endpoint = '${arweave.gatewayUrl}/chunk';

    final res = await dio.post(
      endpoint,
      data: json.encode(chunk),
      cancelToken: _cancelToken,
    );

    if (res.statusCode != 200) {
      final responseError = getResponseErrorFromDioRespose(res);

      if (_fatalChunkUploadErrors.contains(responseError)) {
        throw StateError(
            'Fatal error uploading chunk: $chunkIndex: ${res.statusCode} $responseError');
      } else {
        throw Exception(
            'Received non-fatal error while uploading chunk $chunkIndex: ${res.statusCode} $responseError');
      }
    }
  }

  void cancel() {
    _cancelToken.cancel();
  }
}
