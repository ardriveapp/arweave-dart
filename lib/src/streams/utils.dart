import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/src/models/models.dart';
import 'package:fpdart/fpdart.dart';

import '../crypto/crypto.dart';
import '../utils.dart';
import '../utils/bundle_tag_parser.dart';
import 'data_models.dart';
import 'errors.dart';

Tag createTag(final String name, final String value) => Tag(
      encodeStringToBase64(name),
      encodeStringToBase64(value),
    );

Stream<List<int>> Function() combineStreamAndFunctionList(
  final Stream<List<int>> mainStream,
  final List<Stream<List<int>> Function()> functionList,
) {
  return () async* {
    await for (final data in mainStream) {
      yield data;
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

Stream<List<int>> toStream(final List<int> data) => Stream.fromIterable([data]);

int decodeBytesToLong(final Uint8List list) {
  int value = 0;

  for (int i = list.length - 1; i >= 0; i--) {
    value = value * 256 + list[i];
  }

  return value;
}

Stream<List<int>> Function() createByteRangeStream(
  final Stream<List<int>> stream,
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
      final chunkStart = start - currentBytePosition;
      final chunkEnd =
          remainingBytes < chunk.length ? remainingBytes : chunk.length;

      if (chunkStart < chunkEnd) {
        yield chunk.sublist(chunkStart, chunkEnd);
      }

      currentBytePosition += chunk.length;
    }
  };
}

TaskEither<DataItemError, Uint8List> deepHashTaskEither(
  final List<Stream<List<int>>> inputs,
) {
  return TaskEither.tryCatch(() async {
    return await deepHash(inputs);
  }, (error, _) => DeepHashError());
}

TaskEither<DataItemError, SignDataItemResult> signDataItemTaskEither({
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

TaskEither<DataItemError, String> getOwnerTaskEither(final Wallet wallet) =>
    TaskEither.tryCatch(() async {
      return await wallet.getOwner();
    }, (error, _) => GetWalletOwnerError());

TaskEither<DataItemError, bool> verifySignatureTaskEither({
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

TaskEither<DataItemError, Uint8List> decodeBase64ToBytesTaskEither(
  final String input,
) {
  return TaskEither.tryCatch(() async {
    return decodeBase64ToBytes(input);
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<DataItemError, Uint8List> decodeAndCheckTargetTaskEither(
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

TaskEither<DataItemError, Uint8List> decodeAndCheckAnchorTaskEither(
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

TaskEither<DataItemError, Uint8List> serializeTagsTaskEither(
  final List<Tag> tags,
) {
  return TaskEither.tryCatch(() async {
    return serializeTags(tags: tags);
  }, (error, _) => SerializeTagsError());
}
