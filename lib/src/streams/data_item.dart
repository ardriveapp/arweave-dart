import 'dart:async';
import 'dart:convert';

import 'package:arweave/utils.dart';
import 'package:async/async.dart';

import '../crypto/crypto.dart';
import '../models/models.dart';
import '../utils/bundle_tag_parser.dart';
import 'utils.dart';

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
  required Stream<List<int>> stream,
  required String id,
  required int length,
}) async {
  int byteIndex = 0;
  final reader = ChunkedStreamReader(stream);

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
      dataLength: dataLength);
}

class ProcessedDataItem {
  final String id;
  final String signature;
  final String owner;
  final String target;
  final String anchor;
  final List<int> tags;
  final int dataLength;

  ProcessedDataItem({
    required this.id,
    required this.signature,
    required this.owner,
    required this.target,
    required this.anchor,
    required this.tags,
    required this.dataLength,
  });

  Map<String, dynamic> toMap() {
    return {
      'signature': signature,
      'owner': owner,
      'target': target,
      'anchor': anchor,
      'tags': tags,
      'dataLength': dataLength,
    };
  }
}
