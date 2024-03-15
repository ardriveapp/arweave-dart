import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/utils.dart';
import 'package:arweave/src/utils/bundle_tag_parser.dart';
import 'package:arweave/utils.dart';
import 'package:async/async.dart';
import 'package:fpdart/fpdart.dart';

import '../crypto/crypto.dart';
import 'errors.dart';

DataItemTaskEither createDataItemTaskEither({
  required final Wallet wallet,
  required final DataStreamGenerator dataStream,
  required final int dataStreamSize,
  final String target = '',
  final String anchor = '',
  final List<Tag> tags = const [],
}) {
  return getOwnerTaskEither(wallet).flatMap((owner) =>
      decodeBase64ToBytesTaskEither(owner).flatMap((ownerBytes) =>
          decodeBase64ToBytesTaskEither(target).flatMap((targetBytes) {
            if (target.isNotEmpty && targetBytes.length != 32) {
              return TaskEither.left(InvalidTargetSizeError());
            }

            return decodeBase64ToBytesTaskEither(anchor).flatMap((anchorBytes) {
              if (anchor.isNotEmpty && anchorBytes.length != 32) {
                return TaskEither.left(InvalidAnchorSizeError());
              }

              final tagsBytes = serializeTags(tags: tags);

              return deepHashStreamTaskEither([
                toStream(utf8.encode('dataitem')),
                toStream(utf8.encode('1')), // Transaction format
                toStream(utf8.encode('1')), // Signature type
                toStream(ownerBytes),
                toStream(targetBytes),
                toStream(anchorBytes),
                toStream(tagsBytes),
                dataStream(),
              ]).flatMap((signatureData) => signDataItemTaskEither(
                          wallet: wallet, signatureData: signatureData)
                      .flatMap((signResult) {
                    final dataItemHeaders = [
                      ...shortTo2ByteArray(1),
                      ...signResult.signature,
                      ...ownerBytes,
                      ...(targetBytes.isEmpty ? [0] : [1]),
                      ...targetBytes,
                      ...(anchorBytes.isEmpty ? [0] : [1]),
                      ...anchorBytes,
                      ...longTo8ByteArray(tags.length),
                      ...longTo8ByteArray(tagsBytes.lengthInBytes),
                      ...tagsBytes,
                    ];

                    final dataItemStreamGenerator =
                        combineStreamAndFunctionList(
                            toStream(dataItemHeaders), [dataStream]);

                    return TaskEither.of(DataItemResult(
                      id: signResult.id,
                      dataItemSize: dataItemHeaders.length + dataStreamSize,
                      dataSize: dataStreamSize,
                      streamGenerator: dataItemStreamGenerator,
                    ));
                  }));
            });
          })));
}

Future<ProcessedDataItem> processDataItem({
  required Stream<Uint8List> Function() dataItemStreamGenerator,
  required String id,
  required int length,
  required SignatureConfig signatureConfig,
}) async {
  int byteIndex = 0;
  final reader = ChunkedStreamReader(dataItemStreamGenerator());

  // get signature type
  final signatureType = decodeBytesToLong(await reader.readBytes(2));
  byteIndex += 2;

  // get signature
  final signature = await reader.readBytes(signatureConfig.signatureLength);
  byteIndex += signatureConfig.signatureLength;

  // get owner
  final owner = await reader.readChunk(signatureConfig.publicKeyLength);
  byteIndex += signatureConfig.publicKeyLength;

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
  final tagsBytes = decodeBytesToLong(await reader.readBytes(8));
  byteIndex += 8;

  // get tags bytes length
  final tagsBytesLenthBytes = await reader.readBytes(8);
  final tagsBytesLength = decodeBytesToLong(tagsBytesLenthBytes);
  byteIndex += 8;

  // get tags bytes
  final tags = await reader.readChunk(tagsBytesLength);
  byteIndex += tagsBytesLength;

  // get data
  final dataLength = length - byteIndex;
  final dataStream =
      reader.readStream(dataLength).map((list) => Uint8List.fromList(list));
  final dataStart = byteIndex;
  final dataEnd = length;
  final dataStreamGenerator =
      createByteRangeStream(dataItemStreamGenerator(), dataStart, dataEnd);

  // verify
  final signatureData = await deepHashStream([
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

  final signVerification = await signatureConfig.verify(
      signatureData, signature, encodeBytesToBase64(owner));

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
