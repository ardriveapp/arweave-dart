import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/streams/data_item.dart';
import 'package:arweave/utils.dart';
import 'package:test/test.dart';
import 'fixtures/test_wallet.dart';
import 'deserialize_tags.dart' if (dart.library.io) 'deserialize_tags_io.dart';

void main() async {
  final wallet = getTestWallet();
  final walletOwner = await wallet.getOwner();

  final data = utf8.encode('Hello World!');

  Future<Stream<List<int>>> dataStreamGenerator() async {
    return Stream.fromIterable([data]);
  }

  final tags = [
    Tag(
      encodeStringToBase64('First-Tag'),
      encodeStringToBase64('First-Value'),
    ),
    Tag(
      encodeStringToBase64('Second-Tag'),
      encodeStringToBase64('Second-Value'),
    ),
  ];

  const expectedDataItemId = 'PKvhRDCiv_gpusxagkfTdjWJrp1RazFuxl04E6FUQqs';
  const expectedDataItemSize = 1104;
  late String dataItemId;
  late int dataItemSize;
  late Future<Stream<List<int>>> Function() dataItemDataGenerator;
  late ProcessedDataItem processedDataItem;

  Future<(String, int, Future<Stream<List<int>>> Function())>
      dataItemGenerator() async => await createDataItem(
            wallet: wallet,
            tags: tags,
            dataStreamGenerator: dataStreamGenerator,
            dataSize: data.length,
          );

  group('[streams][data_item]', () {
    test('create and sign data item', () async {
      final dataItem = await dataItemGenerator();
      dataItemId = dataItem.$1;
      dataItemSize = dataItem.$2;
      dataItemDataGenerator = dataItem.$3;
      final dataItemStream = await dataItemDataGenerator();

      expect(dataItemId, expectedDataItemId);
      expect(dataItemSize, expectedDataItemSize);
      expect(dataItemDataGenerator, isA<Function>());
      expect(dataItemStream, isA<Stream<List<int>>>());
    });

    test('process data item', () async {
      final dataItem = await dataItemGenerator();
      final id = dataItem.$1;
      final dataItemSize = dataItem.$2;
      final dataItemDataGenerator = dataItem.$3;
      final dataItemStream = await dataItemDataGenerator();

      processedDataItem = (await processDataItem(
        stream: dataItemStream,
        id: id,
        length: dataItemSize,
      ));

      expect(processedDataItem.id, expectedDataItemId);
      expect(processedDataItem.owner, walletOwner);
      expect(processedDataItem.target, '');
      expect(processedDataItem.anchor, '');
      expect(processedDataItem.dataLength, data.length);
    });
    test('verify tags', () {
      final tags = deserializeTags(buffer: processedDataItem.tags);
      for (var i = 0; i < tags.length; i++) {
        final tag = tags[i];
        print(decodeStringFromBase64(tag.name));
        print(decodeStringFromBase64(tag.value));
      }
    }, onPlatform: {
      'vm': Skip('deserializeTags currently only works with js')
    });
  });
}
