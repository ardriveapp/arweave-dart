import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/src/api/api.dart';
import 'package:arweave/src/models/models.dart';
import 'package:async/async.dart';
import 'package:fpdart/fpdart.dart';

import '../crypto/crypto.dart';
import '../utils.dart';
import '../utils/bundle_tag_parser.dart';
import 'data_models.dart';
import 'deep_hash_stream.dart';
import 'errors.dart';

Tag createTag(final String name, final String value) => Tag(
      encodeStringToBase64(name),
      encodeStringToBase64(value),
    );

Stream<Uint8List> Function() combineStreamAndFunctionList(
  final Stream<List<int>> mainStream,
  final List<Stream<Uint8List> Function()> functionList,
) {
  return () async* {
    await for (final data in mainStream) {
      yield Uint8List.fromList(data);
    }

    for (final function in functionList) {
      final subStream = function();
      await for (final element in subStream) {
        yield element;
      }
    }
  };
}

String toBase64Url(final String base64) =>
    base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

Stream<Uint8List> toStream(final List<int> data) =>
    Stream.fromIterable([data]).map((list) => Uint8List.fromList(list));

int decodeBytesToLong(final Uint8List list) {
  int value = 0;

  for (int i = list.length - 1; i >= 0; i--) {
    value = value * 256 + list[i];
  }

  return value;
}

Stream<Uint8List> Function() createByteRangeStream(
  final Stream<Uint8List> stream,
  final int start,
  final int end,
) {
  return () async* {
    int currentBytePosition = 0;

    await for (final chunk in stream) {
      if (currentBytePosition >= end) {
        break;
      }

      final remainingBytes = end - currentBytePosition;
      final chunkStart = (start - currentBytePosition).clamp(0, chunk.length);
      final chunkEnd =
          remainingBytes < chunk.length ? remainingBytes : chunk.length;

      if (chunkStart < chunkEnd) {
        yield Uint8List.fromList(chunk.sublist(chunkStart, chunkEnd));
      }

      currentBytePosition += chunk.length;
    }
  };
}

TaskEither<StreamTransactionError, Uint8List> deepHashStreamTaskEither(
  final List<Stream<Uint8List>> inputs,
) {
  return TaskEither.tryCatch(() async {
    return await deepHashStream(inputs);
  }, (error, _) => DeepHashStreamError());
}

TaskEither<StreamTransactionError, Uint8List> deepHashTaskEither(
  final List<Object> inputs,
) {
  return TaskEither.tryCatch(() async {
    return await deepHash(inputs);
  }, (error, _) {
    print(error);
    return DeepHashError();
  });
}

TaskEither<StreamTransactionError, SignDataItemResult> signDataItemTaskEither({
  required final Wallet wallet,
  required final Uint8List signatureData,
}) {
  return TaskEither.tryCatch(() async {
    final signature = await wallet.sign(signatureData);
    final idHash = await sha256.hash(signature);

    return SignDataItemResult(
      id: encodeBytesToBase64(idHash.bytes),
      signature: signature,
    );
  }, (error, _) => SignatureError());
}

TaskEither<StreamTransactionError, String> getOwnerTaskEither(
        final Wallet wallet) =>
    TaskEither.tryCatch(() async {
      return await wallet.getOwner();
    }, (error, _) => GetWalletOwnerError());

TaskEither<StreamTransactionError, bool> verifySignatureTaskEither({
  required final Uint8List owner,
  required final Uint8List signature,
  required final Uint8List signatureData,
  required final String expectedId,
}) {
  return TaskEither.tryCatch(() async {
    final idHash = await sha256.hash(signature);
    final id = encodeBytesToBase64(idHash.bytes);

    if (expectedId != id) {
      throw Exception("ID doesn't match signature");
    }

    final signVerification = await rsaPssVerify(
        input: signatureData,
        signature: signature,
        modulus: decodeBytesToBigInt(owner),
        publicExponent: BigInt.from(65537));

    if (!signVerification) {
      throw Exception("Invalid signature");
    }

    return signVerification;
  }, (error, _) => SignatureError());
}

TaskEither<StreamTransactionError, Uint8List> decodeBase64ToBytesTaskEither(
  final String input,
) {
  return TaskEither.tryCatch(() async {
    return decodeBase64ToBytes(input);
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<StreamTransactionError, Uint8List> decodeAndCheckTargetTaskEither(
  final String target,
) {
  return TaskEither.tryCatch(() async {
    final targetBytes = decodeBase64ToBytes(target);
    if (targetBytes.length != 32) {
      TaskEither.left(InvalidTargetSizeError());
    }
    return targetBytes;
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<StreamTransactionError, Uint8List> decodeAndCheckAnchorTaskEither(
  final String target,
) {
  return TaskEither.tryCatch(() async {
    final anchorBytes = decodeBase64ToBytes(target);
    if (anchorBytes.length != 32) {
      TaskEither.left(InvalidAnchorSizeError());
    }
    return anchorBytes;
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<StreamTransactionError, Uint8List> serializeTagsTaskEither(
  final List<Tag> tags,
) {
  return TaskEither.tryCatch(() async {
    return serializeTags(tags: tags);
  }, (error, _) => SerializeTagsError());
}

class PrepareChunksResult {
  final TransactionChunksWithProofs chunks;
  final String dataRoot;

  PrepareChunksResult({
    required this.chunks,
    required this.dataRoot,
  });
}

TaskEither<StreamTransactionError, PrepareChunksResult> prepareChunksTaskEither(
  final DataStreamGenerator dataStreamGenerator,
) {
  return generateTransactionChunksTaskEither(dataStreamGenerator)
      .flatMap((chunks) {
    final dataRoot = encodeBytesToBase64(chunks.dataRoot);
    return TaskEither.of(PrepareChunksResult(
      chunks: chunks,
      dataRoot: dataRoot,
    ));
  });
}

TaskEither<StreamTransactionError, TransactionChunksWithProofs>
    generateTransactionChunksTaskEither(
            DataStreamGenerator dataStreamGenerator) =>
        TaskEither.tryCatch(
            () async => await generateTransactionChunksFromStream(
                dataStreamGenerator()),
            (e, s) => GenerateTransactionChunksError());

Stream<TransactionChunk> getChunks(Stream<Uint8List> dataStream,
    TransactionChunksWithProofs chunks, String dataRoot, int dataSize) async* {
  final chunker = ChunkedStreamReader(dataStream);

  for (var i = 0; i < chunks.chunks.length; i++) {
    final chunk = chunks.chunks[i];
    final proof = chunks.proofs[i];

    final chunkSize = chunk.maxByteRange - chunk.minByteRange;
    final chunkData = await chunker.readBytes(chunkSize);

    yield TransactionChunk(
      dataRoot: dataRoot,
      dataSize: dataSize.toString(),
      dataPath: encodeBytesToBase64(proof.proof),
      offset: proof.offset.toString(),
      chunk: encodeBytesToBase64(chunkData),
    );
  }
  await chunker.cancel();
}

TaskEither<StreamTransactionError, String> getTxAnchor(String? anchor) {
  if (anchor != null) {
    return TaskEither.of(anchor);
  }

  return TaskEither.tryCatch(() async {
    return await ArweaveApi().get('tx_anchor').then((res) => res.body);
  }, (error, _) => GetTxAnchorError());
}

TaskEither<StreamTransactionError, BigInt> getTxPrice(
    BigInt? reward, int byteSize, String? targetAddress) {
  if (reward != null) {
    return TaskEither.of(reward);
  }

  final endpoint = targetAddress != null
      ? 'price/$byteSize/$targetAddress'
      : 'price/$byteSize';

  return TaskEither.tryCatch(() async {
    return await ArweaveApi()
        .get(endpoint)
        .then((res) => BigInt.parse(res.body));
  }, (error, _) => GetTxPriceError());
}
