import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/utils.dart';
import 'package:async/async.dart';

import 'crypto/crypto.dart';
import 'models/models.dart';
import 'utils/bundle_tag_parser.dart';

Future<(String, int, Future<Stream<List<int>>> Function())> createBdi({
  required Wallet wallet,
  required List<
          Future<(String, int, Future<Stream<List<int>>> Function())>
              Function()>
      dataItemsGenerator,
}) async {
  final dataItemsLength = dataItemsGenerator.length;
  final headers = Uint8List(dataItemsLength * 64);
  int dataItemsSize = 0;

  for (var i = 0; i < dataItemsLength; i++) {
    final dataItemGenerator = dataItemsGenerator[i];
    final dataItem = await dataItemGenerator();
    final id = decodeBase64ToBytes(dataItem.$1);
    final dataItemLength = dataItem.$2;

    dataItemsSize += dataItemLength;

    final header = Uint8List(64);

    // Set offset
    header.setAll(0, longTo32ByteArray(dataItemLength));

    // Set id
    header.setAll(32, id);

    // Add header to array of headers
    headers.setAll(64 * i, header);
  }

  final bundleHeaders = [
    longTo32ByteArray(dataItemsLength),
    headers,
  ];

  Future<Stream<List<int>>> bundleGenerator() async {
    return concatenateStreams([
      Stream.fromIterable(bundleHeaders),
      ...(await getStreams(dataItemsGenerator)),
    ]);
  }

  return await createDataItem(
      wallet: wallet,
      dataStreamGenerator: bundleGenerator,
      dataSize: bundleHeaders.length + dataItemsSize);
}

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

  final anchorBytes = decodeBase64ToBytes(anchor);

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

Future<List<Map<String, dynamic>>> processBundle(
  Future<Stream<List<int>>> Function() streamGenerator,
) async {
  print('processBundle');
  final stream = await streamGenerator();
  final reader = ChunkedStreamReader(stream);

  final List<Map<String, dynamic>> items;

  int byteIndex = 0;
  try {
    // set numberOfDataItems
    final numberOfDataItems = decodeBytesToLong(await reader.readBytes(32));
    print(numberOfDataItems);
    byteIndex += 32;

    // set headers
    final headersBytesLength = numberOfDataItems * 64;
    List<int> headersBytes = await reader.readChunk(headersBytesLength);
    final List<(int, String)> headers = List.filled(numberOfDataItems, (0, ""));
    items = List.filled(numberOfDataItems, {});

    for (var i = 0; i < headersBytesLength; i += 64) {
      final id =
          toBase64Url(base64Encode(headersBytes.sublist(i + 32, i + 64)));

      headers[i ~/ 64] = (
        decodeBytesToLong(Uint8List.fromList(headersBytes.sublist(i, i + 32))),
        id,
      );
      items[i ~/ 64] = {'id': id};
    }
    byteIndex += headersBytesLength;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final itemBytesLength = headers[i].$1;

      final dataItemInfo = await processDataItem(
          reader.readStream(itemBytesLength), item['id'], itemBytesLength);

      final int dataLength = dataItemInfo['dataLength'];
      final start = byteIndex + itemBytesLength - dataLength;
      final end = start + dataLength;

      item['signature'] = dataItemInfo['signature'];
      item['owner'] = dataItemInfo['owner'];
      item['target'] = dataItemInfo['target'];
      item['anchor'] = dataItemInfo['anchor'];
      item['tags'] = dataItemInfo['tags'];
      item['data'] = byteRangeStream(await streamGenerator(), start, end);

      byteIndex += itemBytesLength;
    }
  } finally {
    reader.cancel();
  }

  return items;
}

processDataItem(Stream<List<int>> stream, String id, int length) async {
  print(length);
  int byteIndex = 0;
  final reader = ChunkedStreamReader(stream);
  print('1: $byteIndex');

  // get signature type
  final signatureType = decodeBytesToLong(await reader.readBytes(2));
  byteIndex += 2;
  print('2: $byteIndex');

  // get signature
  final signature = await reader.readBytes(512);
  byteIndex += 512;
  print('3: $byteIndex');

  // get owner
  final owner = await reader.readChunk(512);
  byteIndex += 512;
  print('4: $byteIndex');

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
  print('5: $byteIndex');

  // get tags length
  final tagsBytes = decodeBytesToLong(await reader.readBytes(8));
  byteIndex += 8;
  print('6: $byteIndex');

  // get tags bytes length
  final lala = await reader.readBytes(8);
  final tagsBytesLength = decodeBytesToLong(lala);
  byteIndex += 8;
  print('7: $byteIndex');
  print(lala);
  print(tagsBytesLength);

  // get tags bytes
  final tags = await reader.readChunk(tagsBytesLength);
  byteIndex += tagsBytesLength;
  print('8: $byteIndex');

  // get data
  print('legth: $length');
  print('byteIndex: $byteIndex');
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

  return {
    'signature': signature,
    'owner': owner,
    'target': target,
    'anchor': anchor,
    'tags': tags,
    'dataLength': dataLength,
  };
}

int decodeBytesToLong(Uint8List list) {
  int value = 0;

  for (int i = list.length - 1; i >= 0; i--) {
    value = value * 256 + list[i];
  }

  return value;
}

String toBase64Url(String base64) {
  return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

Stream<List<int>> toStream(data) {
  return Stream.fromIterable([data]);
}

Stream<List<int>> byteRangeStream(
    Stream<List<int>> stream, int start, int end) async* {
  int currentBytePosition = 0;

  await for (List<int> chunk in stream) {
    int chunkStart = 0;
    int chunkEnd = chunk.length;

    if (currentBytePosition + chunk.length < start) {
      currentBytePosition += chunk.length;
      continue;
    }

    if (currentBytePosition < start) {
      chunkStart = start - currentBytePosition;
    }

    if (currentBytePosition + chunk.length > end) {
      chunkEnd = end - currentBytePosition + 1;
    }

    yield chunk.sublist(chunkStart, chunkEnd);

    currentBytePosition += chunk.length;

    if (currentBytePosition > end) {
      break;
    }
  }
}

Stream<List<int>> concatenateStreams(List<Stream<List<int>>> streams) async* {
  for (var stream in streams) {
    yield* stream;
  }
}

Future<List<Stream<List<int>>>> getStreams(
    List<Future<(String, int, Future<Stream<List<int>>> Function())> Function()>
        functions) async {
  List<Stream<List<int>>> result = [];

  for (var function in functions) {
    var futureTuple = await function();
    var futureStreamFunction = futureTuple.$3;
    var stream = await futureStreamFunction();
    result.add(stream);
  }

  return result;
}
