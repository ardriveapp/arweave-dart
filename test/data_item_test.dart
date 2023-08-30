import 'dart:convert';

import 'package:arweave/src/streams/data_item.dart';
import 'package:arweave/src/streams/data_models.dart';
import 'package:arweave/src/streams/errors.dart';
import 'package:arweave/src/streams/utils.dart';
import 'package:fpdart/fpdart.dart';
import 'package:test/test.dart';
import 'fixtures/test_wallet.dart';
import 'deserialize_tags.dart' if (dart.library.io) 'deserialize_tags_io.dart';

void main() async {
  final wallet = getTestWallet();
  final walletOwner = await wallet.getOwner();

  final dataText = 'Hello World!';

  final data = utf8.encode(dataText);

  Stream<List<int>> dataStreamGenerator() {
    return Stream.fromIterable([data]);
  }

  final tags = [
    createTag('First-Tag', 'First-Value'),
    createTag('Second-Tag', 'Second-Value'),
  ];

  const expectedDataItemId = 'PKvhRDCiv_gpusxagkfTdjWJrp1RazFuxl04E6FUQqs';
  const expectedDataItemSize = 1104;

  group('[streams][data_item]', () {
    test('create and sign data item', () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Right>());

      dataItemTask.match((error) {
        expect(error, None());
      }, (dataItem) {
        expect(dataItem.id, expectedDataItemId);
        expect(dataItem.size, expectedDataItemSize);
        expect(dataItem.stream, isA<DataStreamGenerator>());

        final dataStream = dataItem.stream();

        expect(dataStream, emitsThrough(data));
      });
    });

    test('return anchor size error when creating dataitem', () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        anchor: expectedDataItemId + '1',
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Left>());

      dataItemTask.match((error) {
        expect(error, isA<InvalidAnchorSizeError>());
      }, (dataItem) {
        expect(dataItem, None());
      });
    });

    test(
        'return DecodeBase64ToBytesError if anchor is not base64 when creating dataitem',
        () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        anchor: expectedDataItemId + '%',
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Left>());

      dataItemTask.match((error) {
        expect(error, isA<DecodeBase64ToBytesError>());
      }, (dataItem) {
        expect(dataItem, None());
      });
    });

    test('return target size error when creating dataitem', () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        target: expectedDataItemId + '1',
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Left>());

      dataItemTask.match((error) {
        expect(error, isA<InvalidTargetSizeError>());
      }, (dataItem) {
        expect(dataItem, None());
      });
    });

    test(
        'return DecodeBase64ToBytesError if target is not base64 when creating dataitem',
        () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        target: expectedDataItemId + '%',
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Left>());

      dataItemTask.match((error) {
        expect(error, isA<DecodeBase64ToBytesError>());
      }, (dataItem) {
        expect(dataItem, None());
      });
    });

    test('process data item', () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Right>());

      await dataItemTask.match((error) {
        expect(error, None());
      }, (dataItem) async {
        final processedDataItem = await processDataItem(
          dataItemStreamGenerator: dataItem.stream,
          id: dataItem.id,
          length: dataItem.size,
        );

        expect(processedDataItem.id, expectedDataItemId);
        expect(processedDataItem.owner, walletOwner);
        expect(processedDataItem.target, '');
        expect(processedDataItem.anchor, '');
        expect(processedDataItem.dataLength, data.length);

        final dataStream = processedDataItem.dataStreamGenerator;

        final receivedData = [];
        await for (List<int> bytes in dataStream()) {
          receivedData.addAll(bytes);
        }

        expect(receivedData, data);
      });
    });

    test('verify tags', () async {
      final dataItemTaskEither = createDataItemTaskEither(
        wallet: wallet,
        tags: tags,
        dataStream: dataStreamGenerator,
        dataSize: data.length,
      );

      final dataItemTask = await dataItemTaskEither.run();

      expect(dataItemTask, isA<Right>());

      await dataItemTask.match((error) {
        expect(error, None());
      }, (dataItem) async {
        final processedDataItem = await processDataItem(
          dataItemStreamGenerator: dataItem.stream,
          id: dataItem.id,
          length: dataItem.size,
        );
        final deserializedTags =
            deserializeTags(buffer: processedDataItem.tags);

        final receivedTags = [];

        for (var i = 0; i < deserializedTags.length; i++) {
          final tag = deserializedTags[i];
          receivedTags.add(tag);
        }

        expect(receivedTags, tags);
      });
    }, onPlatform: {
      'vm': Skip('deserializeTags currently only works with js')
    });
  });
}
