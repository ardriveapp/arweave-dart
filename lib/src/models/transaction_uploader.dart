import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/api/api.dart';

import '../utils.dart';

/// Maximum amount of chunks we will upload in the body.
const MAX_CHUNKS_IN_BODY = 1;
const MAX_CHUNKS_BATCH_SIZE = 100;

/// Amount we will delay on receiving an error response but do want to continue.
const ERROR_DELAY = 1000 * 40;

/// Errors from /chunk we should never try and continue on.
const FATAL_CHUNK_UPLOAD_ERRORS = [
  'invalid_json',
  'chunk_too_big',
  'data_path_too_big',
  'offset_too_big',
  'data_size_too_big',
  'chunk_proof_ratio_not_attractive',
  'invalid_proof'
];

class TransactionUploader {
  int _chunkOffset = 0;
  bool _txPosted = false;
  int _lastRequestTimeEnd = 0;
  int _totalErrors = 0;

  int lastResponseStatus = 0;
  String lastResponseError = '';
  List<TransactionChunk> failedChunks = [];

  final Transaction _transaction;
  final ArweaveApi _api;
  final Random _random = Random();

  TransactionUploader(Transaction transaction, ArweaveApi api,
      {bool forDataOnly = false})
      : _transaction = transaction,
        _api = api,
        _txPosted = forDataOnly {
    if (transaction.chunks == null) {
      throw ArgumentError('Transaction chunks not prepared.');
    }
  }

  TransactionUploader._({
    required ArweaveApi api,
    required Transaction transaction,
    int? chunkIndex,
    bool? txPosted,
    int? lastRequestTimeEnd,
    int? lastResponseStatus,
    String? lastResponseError,
  })  : _api = api,
        _transaction = transaction {
    if (chunkIndex != null) {
      _chunkOffset = chunkIndex;
    }
    if (txPosted != null) {
      _txPosted = txPosted;
    }
    if (lastRequestTimeEnd != null) {
      _lastRequestTimeEnd = lastRequestTimeEnd;
    }
    if (lastResponseStatus != null) {
      this.lastResponseStatus = lastResponseStatus;
    }
    if (lastResponseError != null) {
      this.lastResponseError = lastResponseError;
    }
  }

  bool get isComplete =>
      _txPosted && _chunkOffset >= _transaction.chunks!.chunks.length;
  int get totalChunks => _transaction.chunks!.chunks.length;
  int get uploadedChunks => _chunkOffset;

  /// The progress of the current upload ranging from 0 to 1.
  double get progress => uploadedChunks / totalChunks;

  /// Uploads a chunk of the transaction.
  /// On the first call this posts the transaction
  /// itself and on any subsequent calls uploads the
  /// next chunk until it completes.
  Future<void> uploadChunk() async {
    if (isComplete) throw StateError('Upload is already complete.');

    if (!_txPosted) {
      await _postTransaction();
      return;
    }

    final chunks = _transaction.getChunks(_chunkOffset, MAX_CHUNKS_BATCH_SIZE);

    try {
      await Future.wait(chunks.map((chunk) async {
        final res = await _api.post('chunk', body: json.encode(chunk));
        if (res.statusCode != 200) {
          failedChunks.add(chunk);
        }
      }));
      if (failedChunks.isNotEmpty) {
        await Future.wait(failedChunks.map((chunk) async {
          final res = await _api.post('chunk', body: json.encode(chunk));
          if (res.statusCode == 200) {
            failedChunks.remove(chunk);
          }
        }));
      }
      _chunkOffset += MAX_CHUNKS_BATCH_SIZE;
    } catch (e) {
      print("Error posting to /chunk endpoint: " + e.toString());
    }
  }

  Future<void> _postTransaction() async {
    final uploadInBody = totalChunks <= MAX_CHUNKS_IN_BODY;
    final txJson = _transaction.toJson();

    if (uploadInBody) {
      // TODO: Make async
      if (_transaction.tags.contains(Tag('Bundle-Format', 'binary'))) {
        txJson['data'] = _transaction.data.buffer;
      } else {
        txJson['data'] = encodeBytesToBase64(_transaction.data);
      }
      final res = await _api.post('tx', body: json.encode(txJson));

      _lastRequestTimeEnd = DateTime.now().millisecondsSinceEpoch;
      lastResponseStatus = res.statusCode;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // This transaction and it's data is uploaded.
        _txPosted = true;
        _chunkOffset = MAX_CHUNKS_IN_BODY;
        return;
      }

      throw StateError('Unable to upload transaction: ${res.statusCode}');
    }

    // Post the transaction with no data.
    txJson.remove('data');
    final res = await _api.post('tx', body: json.encode(txJson));

    _lastRequestTimeEnd = DateTime.now().millisecondsSinceEpoch;
    lastResponseStatus = res.statusCode;

    if (!(res.statusCode >= 200 && res.statusCode < 300)) {
      throw StateError('Unable to upload transaction: ${res.statusCode}');
    }

    _txPosted = true;
  }

  static Future<TransactionUploader> deserialize(
      Map<String, dynamic> json, Uint8List data, ArweaveApi api) async {
    final transaction = json['transaction'] != null
        ? Transaction.fromJson(json['transaction'])
        : null;

    await transaction!.setData(data);

    return TransactionUploader._(
      api: api,
      chunkIndex: json['chunkIndex'] as int,
      txPosted: json['txPosted'],
      transaction: transaction,
      lastRequestTimeEnd: json['lastRequestTimeEnd'],
      lastResponseStatus: json['lastResponseStatus'],
      lastResponseError: json['lastResponseError'],
    );
  }

  Map<String, dynamic> serialize() => <String, dynamic>{
        'chunkIndex': _chunkOffset,
        'txPosted': _txPosted,
        'transaction': _transaction.toJson()..['data'] = null,
        'lastRequestTimeEnd': _lastRequestTimeEnd,
        'lastResponseStatus': lastResponseStatus,
        'lastResponseError': lastResponseError,
      };
}
