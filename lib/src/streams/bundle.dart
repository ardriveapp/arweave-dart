import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/utils.dart';
import 'package:async/async.dart';

import '../models/models.dart';
import './utils.dart';
import './data_item.dart';

Future<(String, int, Future<Stream<List<int>>> Function())> createBundle({
  required Wallet wallet,
  required List<
          Future<(String, int, Future<Stream<List<int>>> Function())>
              Function()>
      dataItemsGenerator,
}) async {
  final dataItemsLength = dataItemsGenerator.length;
  final headers = Uint8List(dataItemsLength * 64);
  int dataItemsSize = 0;
  print('createBdi: $dataItemsLength');
  print('dataitemLenght: ${longTo32ByteArray(dataItemsLength)}');

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
    ...longTo32ByteArray(dataItemsLength),
    ...headers,
  ];

  print('bundleHeaders: $bundleHeaders');

  Future<Stream<List<int>>> bundleGenerator() async {
    return concatenateStreams([
      Stream.fromIterable([bundleHeaders]),
      ...(await getStreams(dataItemsGenerator)),
    ]);
  }

  return await createDataItem(
      wallet: wallet,
      dataStreamGenerator: bundleGenerator,
      dataSize: bundleHeaders.length + dataItemsSize);
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
    final numberOfDataItemsBytes = await reader.readBytes(32);
    final numberOfDataItems = decodeBytesToLong(numberOfDataItemsBytes);
    print('numberOfDataItems: $numberOfDataItemsBytes');
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
