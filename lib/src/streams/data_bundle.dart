import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/utils.dart';
import 'package:fpdart/fpdart.dart';

import '../models/models.dart';
import './utils.dart';
import 'data_item.dart';
import 'data_models.dart';
import 'errors.dart';

class DataItemFile {
  final int dataSize;
  final DataStreamGenerator streamGenerator;
  final String target;
  final String anchor;
  final List<Tag> tags;

  const DataItemFile({
    required this.dataSize,
    required this.streamGenerator,
    this.target = '',
    this.anchor = '',
    this.tags = const [],
  });
}

typedef BundledDataItemResult = TaskEither<DataItemError, DataItemResult>;
BundledDataItemResult createBundledDataItemTaskEither({
  required final Wallet wallet,
  required final List<DataItemFile> dataItemFiles,
  required final List<Tag> tags,
}) {
  final List<DataItemTaskEither> dataItemTaskEitherList = [];
  final dataItemCount = dataItemFiles.length;
  for (var i = 0; i < dataItemCount; i++) {
    final dataItem = dataItemFiles[i];

    final dataItemTaskEither = createDataItemTaskEither(
      wallet: wallet,
      dataStream: dataItem.streamGenerator,
      dataStreamSize: dataItem.dataSize,
      target: dataItem.target,
      anchor: dataItem.anchor,
      tags: dataItem.tags,
    );
    dataItemTaskEitherList.add(dataItemTaskEither);
  }

  return createDataBundleTaskEither(dataItemTaskEitherList)
      .flatMap((dataBundle) {
    final dataBundleStream = dataBundle.stream;
    final dataBundleSize = dataBundle.dataBundleStreamSize;

    final bundledDataItemTags = [
      createTag('Bundle-Format', 'binary'),
      createTag('Bundle-Version', '2.0.0'),
      ...tags.map((tag) => createTag(tag.name, tag.value))
    ];

    return createDataItemTaskEither(
      wallet: wallet,
      dataStream: dataBundleStream,
      dataStreamSize: dataBundleSize,
      target: '',
      anchor: '',
      tags: bundledDataItemTags,
    ).flatMap((dataItem) => TaskEither.of(dataItem));
  });
}

DataBundleTaskEither createDataBundleTaskEither(
  final List<DataItemTaskEither> dataItemsTaskEither,
) {
  return dataItemsTaskEither.sequenceTaskEitherSeq().flatMap((dataItems) {
    final dataItemsLength = dataItems.length;
    final headers = Uint8List(dataItemsLength * 64);
    int dataItemsSize = 0;

    for (var i = 0; i < dataItemsLength; i++) {
      final dataItem = dataItems[i];
      final id = decodeBase64ToBytes(dataItem.id);
      final dataItemLength = dataItem.dataItemSize;

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

    final bundleGenerator = combineStreamAndFunctionList(
        Stream.fromIterable([bundleHeaders]),
        dataItems.map((dataItem) => dataItem.streamGenerator).toList());

    return TaskEither.of(DataBundleResult(
      dataBundleStreamSize: bundleHeaders.length + dataItemsSize,
      dataItemsSize: dataItemsSize,
      stream: bundleGenerator,
    ));
  });
}

// Will be refactored to use TaskEither

// Future<List<Map<String, dynamic>>> processBundle(
//   Future<Stream<List<int>>> Function() streamGenerator,
// ) async {
//   print('processBundle');
//   final stream = await streamGenerator();
//   final reader = ChunkedStreamReader(stream);
//
//   final List<Map<String, dynamic>> items;
//
//   int byteIndex = 0;
//   try {
//     // set numberOfDataItems
//     final numberOfDataItemsBytes = await reader.readBytes(32);
//     final numberOfDataItems = decodeBytesToLong(numberOfDataItemsBytes);
//     print('numberOfDataItems: $numberOfDataItemsBytes');
//     byteIndex += 32;
//
//     // set headers
//     final headersBytesLength = numberOfDataItems * 64;
//     List<int> headersBytes = await reader.readChunk(headersBytesLength);
//     final List<(int, String)> headers = List.filled(numberOfDataItems, (0, ""));
//     items = List.filled(numberOfDataItems, {});
//
//     for (var i = 0; i < headersBytesLength; i += 64) {
//       final id =
//           toBase64Url(base64Encode(headersBytes.sublist(i + 32, i + 64)));
//
//       headers[i ~/ 64] = (
//         decodeBytesToLong(Uint8List.fromList(headersBytes.sublist(i, i + 32))),
//         id,
//       );
//       items[i ~/ 64] = {'id': id};
//     }
//     byteIndex += headersBytesLength;
//
//     for (var i = 0; i < items.length; i++) {
//       final item = items[i];
//       final itemBytesLength = headers[i].$1;
//
//       final dataItemInfo = await processDataItem(
//           reader.readStream(itemBytesLength), item['id'], itemBytesLength);
//
//       final int dataLength = dataItemInfo['dataLength'];
//       final start = byteIndex + itemBytesLength - dataLength;
//       final end = start + dataLength;
//
//       item['signature'] = dataItemInfo['signature'];
//       item['owner'] = dataItemInfo['owner'];
//       item['target'] = dataItemInfo['target'];
//       item['anchor'] = dataItemInfo['anchor'];
//       item['tags'] = dataItemInfo['tags'];
//       item['data'] = byteRangeStream(await streamGenerator(), start, end);
//
//       byteIndex += itemBytesLength;
//     }
//   } finally {
//     reader.cancel();
//   }
//
//   return items;
// }
