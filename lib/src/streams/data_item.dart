import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/utils.dart';
import 'package:async/async.dart';
import 'package:fpdart/fpdart.dart';

import '../crypto/crypto.dart';
import '../models/models.dart';
import '../utils/bundle_tag_parser.dart';
import 'utils.dart';

TaskEither<DataItemError, DataItemResult> createDataItemTaskEither({
  required final Wallet wallet,
  required final DataStreamGenerator dataStream,
  required final int dataSize,
  final String target = '',
  final String anchor = '',
  final List<Tag> tags = const [],
}) {
  return TaskEither<DataItemError, DataItemResult>.Do((_) async {
    final owner = await _(getOwnerTaskEither(wallet));
    final ownerBytes = await _(decodeBase64ToBytesTaskEither(owner));
    final targetBytes = await _(decodeAndCheckTargetTaskEither(target));
    final anchorBytes = await _(decodeAndCheckAnchorTaskEither(anchor));
    final tagsBytes = await _(serializeTagsTaskEither(tags));
    final signatureData = await _(
      deepHashTaskEither([
        toStream(utf8.encode('dataitem')),
        toStream(utf8.encode('1')), // Transaction format
        toStream(utf8.encode('1')),
        toStream(ownerBytes),
        toStream(targetBytes),
        toStream(anchorBytes),
        toStream(tagsBytes),
        dataStream(),
      ]),
    );
    final signResult = await _(
      signDataItemTaskEither(
        wallet: wallet,
        signatureData: signatureData,
      ),
    );

    final dataItemHeaders = [
      ...shortTo2ByteArray(1),
      ...signResult.signature,
      ...ownerBytes,
      ...targetBytes.isEmpty ? [0] : [1],
      ...targetBytes,
      ...anchorBytes.isEmpty ? [0] : [1],
      ...anchorBytes,
      ...longTo8ByteArray(tags.length),
      ...longTo8ByteArray(tagsBytes.lengthInBytes),
      ...tagsBytes,
    ];

    dataStreamGenerator() => concatenateStreams([
          Stream.fromIterable([dataItemHeaders]),
          dataStream()
        ]);

    return DataItemResult(
      id: signResult.id,
      size: dataItemHeaders.length + dataSize,
      stream: dataStreamGenerator,
    );
  }).getOrElse((_) => TaskEither.left(DataItemCreationError()));
}

// TaskEither<DataItemError, DataItemResult> createDataItemTaskEither({
//   required final Wallet wallet,
//   required final DataStreamGenerator dataStream,
//   required final int dataSize,
//   final String target = '',
//   final String anchor = '',
//   final List<Tag> tags = const [],
// }) {
//   return getOwnerTaskEither(wallet).flatMap((owner) =>
//       decodeBase64ToBytesTaskEither(owner).flatMap((ownerBytes) =>
//           decodeBase64ToBytesTaskEither(target).flatMap((targetBytes) {
//             if (target.isNotEmpty && targetBytes.length != 32) {
//               return TaskEither.left(InvalidTargetSizeError());
//             }
//
//             return decodeBase64ToBytesTaskEither(anchor).flatMap((anchorBytes) {
//               if (anchor.isNotEmpty && anchorBytes.length != 32) {
//                 return TaskEither.left(InvalidAnchorSizeError());
//               }
//
//               final tagsBytes = serializeTags(tags: tags);
//
//               return deepHashTaskEither([
//                 toStream(utf8.encode('dataitem')),
//                 toStream(utf8.encode('1')), // Transaction format
//                 toStream(utf8.encode('1')),
//                 toStream(ownerBytes),
//                 toStream(targetBytes),
//                 toStream(anchorBytes),
//                 toStream(tagsBytes),
//                 dataStream(),
//               ]).flatMap((signatureData) => signDataItemTaskEither(
//                           wallet: wallet, signatureData: signatureData)
//                       .flatMap((signResult) {
//                     final dataItemHeaders = [
//                       ...shortTo2ByteArray(1),
//                       ...signResult.signature,
//                       ...ownerBytes,
//                       ...(targetBytes.isEmpty ? [0] : [1]),
//                       ...targetBytes,
//                       ...(anchorBytes.isEmpty ? [0] : [1]),
//                       ...anchorBytes,
//                       ...longTo8ByteArray(tags.length),
//                       ...longTo8ByteArray(tagsBytes.lengthInBytes),
//                       ...tagsBytes,
//                     ];
//
//                     dataStreamGenerator() => concatenateStreams([
//                           Stream.fromIterable([dataItemHeaders]),
//                           dataStream()
//                         ]);
//
//                     return TaskEither.of(DataItemResult(
//                       id: signResult.id,
//                       size: dataItemHeaders.length + dataSize,
//                       stream: dataStreamGenerator,
//                     ));
//                   }));
//             });
//           })));
// }

Future<(String, int, Future<Stream<List<int>>> Function())> createDataItem({
  required Wallet wallet,
  String target = '',
  String anchor = '',
  List<Tag> tags = const [],
  required Future<Stream<List<int>>> Function() dataStreamGenerator,
  required int dataSize,
}) async {
  final owner = await wallet.getOwner();
  final ownerBytes = decodeBase64ToBytes(owner);

  final targetBytes = decodeBase64ToBytes(target);
  if (target.isNotEmpty && targetBytes.length != 32) {
    throw Exception('Invalid target');
  }

  final anchorBytes = decodeBase64ToBytes(anchor);
  if (anchor.isNotEmpty && anchorBytes.length != 32) {
    throw Exception('Invalid anchor');
  }

  final tagsBytes = serializeTags(tags: tags);

  final signatureData = await deepHash([
    toStream(utf8.encode('dataitem')),
    toStream(utf8.encode('1')), // Transaction format
    toStream(utf8.encode('1')),
    toStream(ownerBytes),
    toStream(targetBytes),
    toStream(anchorBytes),
    toStream(tagsBytes),
    await dataStreamGenerator(),
  ]);

  final rawSignature = await wallet.sign(signatureData);

  final idHash = await sha256.hash(rawSignature);

  final id = encodeBytesToBase64(idHash.bytes);

  final dataItemHeaders = [
    ...shortTo2ByteArray(1),
    ...rawSignature,
    ...ownerBytes,
    ...(targetBytes.isEmpty ? [0] : [1]),
    ...targetBytes,
    ...(anchorBytes.isEmpty ? [0] : [1]),
    ...anchorBytes,
    ...longTo8ByteArray(tags.length),
    ...longTo8ByteArray(tagsBytes.lengthInBytes),
    ...tagsBytes,
  ];

  dataItemStream() async {
    return concatenateStreams([
      Stream.fromIterable([dataItemHeaders]),
      await dataStreamGenerator()
    ]);
  }

  return (id, dataItemHeaders.length + dataSize, dataItemStream);
}

Future<ProcessedDataItem> processDataItem({
  required Stream<List<int>> Function() dataItemStreamGenerator,
  required String id,
  required int length,
}) async {
  int byteIndex = 0;
  final reader = ChunkedStreamReader(dataItemStreamGenerator());

  // get signature type
  final signatureType = decodeBytesToLong(await reader.readBytes(2));
  byteIndex += 2;

  // get signature
  final signature = await reader.readBytes(512);
  byteIndex += 512;

  // get owner
  final owner = await reader.readChunk(512);
  byteIndex += 512;

  // get target
  final targetExists = (await reader.readChunk(1))[0] == 1;
  byteIndex += 1;

  List<int> target = [];
  if (targetExists) {
    target = await reader.readChunk(32);
    byteIndex += 32;
  }

  // get anchor
  final anchorExists = (await reader.readChunk(1))[0] == 1;
  byteIndex += 1;

  List<int> anchor = [];
  if (anchorExists) {
    anchor = await reader.readChunk(32);
    byteIndex += 32;
  }

  // get tags length
  // final tagsBytes = decodeBytesToLong(await reader.readBytes(8));
  await reader.readBytes(8);
  byteIndex += 8;

  // get tags bytes length
  final lala = await reader.readBytes(8);
  final tagsBytesLength = decodeBytesToLong(lala);
  byteIndex += 8;

  // get tags bytes
  final tags = await reader.readChunk(tagsBytesLength);
  byteIndex += tagsBytesLength;

  // get data
  final dataLength = length - byteIndex;
  final dataStream = reader.readStream(dataLength);
  final dataStart = byteIndex;
  final dataEnd = length;
  dataStreamGenerator() =>
      byteRangeStream(dataItemStreamGenerator(), dataStart, dataEnd);

  // verify
  final signatureData = await deepHash([
    toStream(utf8.encode('dataitem')),
    toStream(utf8.encode('1')), // Transaction format
    toStream(utf8.encode(signatureType.toString())),
    toStream(owner),
    toStream(target),
    toStream(anchor),
    toStream(tags),
    dataStream,
  ]);

  final idHash = await sha256.hash(signature);
  final expectedId = encodeBytesToBase64(idHash.bytes);
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

  return ProcessedDataItem(
    id: id,
    tags: tags,
    signature: encodeBytesToBase64(signature),
    owner: encodeBytesToBase64(owner),
    target: encodeBytesToBase64(target),
    anchor: encodeBytesToBase64(anchor),
    dataLength: dataLength,
    dataStreamGenerator: dataStreamGenerator,
  );
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
    final String target) {
  return TaskEither.tryCatch(() async {
    final targetBytes = decodeBase64ToBytes(target);
    if (targetBytes.length != 32) {
      TaskEither.left(InvalidTargetSizeError());
    }
    return targetBytes;
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<DataItemError, Uint8List> decodeAndCheckAnchorTaskEither(
    final String target) {
  return TaskEither.tryCatch(() async {
    final anchorBytes = decodeBase64ToBytes(target);
    if (anchorBytes.length != 32) {
      TaskEither.left(InvalidAnchorSizeError());
    }
    return anchorBytes;
  }, (error, _) => DecodeBase64ToBytesError());
}

TaskEither<DataItemError, Uint8List> serializeTagsTaskEither(
    final List<Tag> tags) {
  return TaskEither.tryCatch(() async {
    return serializeTags(tags: tags);
  }, (error, _) => SerializeTagsError());
}

abstract class DataItemError {}

class DataItemCreationError extends DataItemError {}

class InvalidTargetSizeError extends DataItemError {}

class InvalidAnchorSizeError extends DataItemError {}

class DeepHashError extends DataItemError {}

class SignatureError extends DataItemError {}

class GetWalletOwnerError extends DataItemError {}

class ProcessedDataItemHeadersError extends DataItemError {}

class DecodeBase64ToBytesError extends DataItemError {}

class SerializeTagsError extends DataItemError {}

class SignDataItemResult {
  final String id;
  final Uint8List signature;

  const SignDataItemResult({
    required this.id,
    required this.signature,
  });
}

typedef DataStreamGenerator = Stream<List<int>> Function();

class DataItemResult {
  final String id;
  final int size;
  final DataStreamGenerator stream;

  const DataItemResult({
    required this.id,
    required this.size,
    required this.stream,
  });
}

class ProcessedDataItem {
  final String id;
  final String signature;
  final String owner;
  final String target;
  final String anchor;
  final List<int> tags;
  final int dataLength;
  final DataStreamGenerator dataStreamGenerator;

  const ProcessedDataItem({
    required this.id,
    required this.signature,
    required this.owner,
    required this.target,
    required this.anchor,
    required this.tags,
    required this.dataLength,
    required this.dataStreamGenerator,
  });
}
