import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/utils.dart';
import 'package:fpdart/fpdart.dart';

import './utils.dart';
import '../crypto/merkle.dart';
import '../models/models.dart';
import 'data_item.dart';
import 'data_models.dart';
import 'errors.dart';

class TransactionResult {
  static const int format = 2;

  final String id;
  final String anchor;
  final String owner;
  final List<Tag> tags;
  final String target;
  final BigInt quantity;
  final String dataRoot;
  final int dataSize;
  final BigInt reward;
  final String signature;
  final Stream<TransactionChunk> Function() chunkStreamGenerator;
  final TransactionChunksWithProofs chunks;

  TransactionResult({
    required this.id,
    required this.anchor,
    required this.owner,
    required this.tags,
    required this.target,
    required this.quantity,
    required this.dataRoot,
    required this.dataSize,
    required this.reward,
    required this.signature,
    required this.chunkStreamGenerator,
    required this.chunks,
  });

  Map<String, dynamic> toJson() {
    return {
      'format': 2,
      'id': id,
      'last_tx': anchor,
      'owner': owner,
      'tags': tags.map((tag) => tag.toJson()).toList(),
      'target': target,
      'quantity': quantity.toString(),
      'data_root': dataRoot,
      'data_size': dataSize.toString(),
      'reward': reward.toString(),
      'signature': signature,
    };
  }
}

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

typedef TransactionTaskEither
    = TaskEither<StreamTransactionError, TransactionResult>;
TransactionTaskEither createTransactionTaskEither({
  required final Wallet wallet,
  String? anchor,
  String? target,
  List<Tag> tags = const [],
  BigInt? quantity,
  BigInt? reward,
  required final DataStreamGenerator dataStreamGenerator,
  required final int dataSize,
}) {
  return getTxAnchor(anchor).flatMap((anchor) =>
      getTxPrice(reward, dataSize, target).flatMap((reward) =>
          getOwnerTaskEither(wallet).flatMap((owner) =>
              prepareChunksTaskEither(dataStreamGenerator)
                  .flatMap((chunksWithProofs) {
                final chunks = chunksWithProofs.chunks;
                final dataRoot = chunksWithProofs.dataRoot;

                final bundleTags = [
                  createTag('Bundle-Format', 'binary'),
                  createTag('Bundle-Version', '2.0.0'),
                  ...tags,
                ];
                final finalQuantity = quantity ?? BigInt.zero;

                return deepHashTaskEither([
                  utf8.encode("2"), // Transaction format
                  decodeBase64ToBytes(owner),
                  decodeBase64ToBytes(target ?? ''),
                  utf8.encode(finalQuantity.toString()),
                  utf8.encode(reward.toString()),
                  decodeBase64ToBytes(anchor),
                  bundleTags
                      .map(
                        (t) => [
                          decodeBase64ToBytes(t.name),
                          decodeBase64ToBytes(t.value),
                        ],
                      )
                      .toList(),
                  utf8.encode(dataSize.toString()),
                  decodeBase64ToBytes(dataRoot),
                ]).flatMap((signatureData) {
                  return signDataItemTaskEither(
                          wallet: wallet, signatureData: signatureData)
                      .flatMap((signResult) {
                    final transaction = TransactionResult(
                      id: signResult.id,
                      anchor: anchor,
                      owner: owner,
                      tags: bundleTags,
                      target: target ?? '',
                      quantity: finalQuantity,
                      dataRoot: dataRoot,
                      dataSize: dataSize,
                      reward: reward,
                      signature: encodeBytesToBase64(signResult.signature),
                      chunkStreamGenerator: () => getChunks(
                        dataStreamGenerator(),
                        chunks,
                        dataRoot,
                        dataSize,
                      ),
                      chunks: chunks,
                    );

                    return TaskEither.of(transaction);
                  });
                });
              }))));
}

typedef BundledDataItemResult
    = Future<TaskEither<StreamTransactionError, DataItemResult>>;
BundledDataItemResult createBundledDataItemTaskEither({
  required final Wallet wallet,
  required final List<DataItemFile> dataItemFiles,
  required final List<Tag> tags,
}) async {
  final List<DataItemResult> dataItemList = [];
  final dataItemCount = dataItemFiles.length;
  for (var i = 0; i < dataItemCount; i++) {
    final dataItem = dataItemFiles[i];
    await createDataItemTaskEither(
      wallet: wallet,
      dataStream: dataItem.streamGenerator,
      dataStreamSize: dataItem.dataSize,
      target: dataItem.target,
      anchor: dataItem.anchor,
      tags: dataItem.tags,
    ).map((dataItem) => dataItemList.add(dataItem)).run();
  }

  return createDataBundleTaskEither(TaskEither.of(dataItemList))
      .flatMap((dataBundle) {
    final dataBundleStream = dataBundle.stream;
    final dataBundleSize = dataBundle.dataBundleStreamSize;

    final bundledDataItemTags = [
      createTag('Bundle-Format', 'binary'),
      createTag('Bundle-Version', '2.0.0'),
      ...tags,
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
  final TaskEither<StreamTransactionError, List<DataItemResult>> dataItems,
) {
  const dataItemHeaderSize = 64;

  return dataItems.flatMap((dataItemResults) {
    final dataItemsLength = dataItemResults.length;
    final headers = Uint8List(dataItemsLength * dataItemHeaderSize);
    int dataItemsSize = 0;

    for (var i = 0; i < dataItemsLength; i++) {
      final dataItem = dataItemResults[i];
      final id = decodeBase64ToBytes(dataItem.id);
      final dataItemLength = dataItem.dataItemSize;

      dataItemsSize += dataItemLength;

      final header = Uint8List(dataItemHeaderSize);

      // Set offset
      header.setAll(0, longTo32ByteArray(dataItemLength));

      // Set id
      header.setAll(32, id);

      // Add header to array of headers
      headers.setAll(dataItemHeaderSize * i, header);
    }

    final bundleHeaders = [
      ...longTo32ByteArray(dataItemsLength),
      ...headers,
    ];

    final bundleGenerator = combineStreamAndFunctionList(
        Stream.fromIterable([bundleHeaders]),
        dataItemResults.map((dataItem) => dataItem.streamGenerator).toList());

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
