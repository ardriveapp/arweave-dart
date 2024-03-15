@TestOn('browser')
@Timeout(Duration(minutes: 2))

import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/crypto/crypto.dart';
import 'package:test/test.dart';

import 'fixtures/test_wallet.dart';
import 'snapshots/data_bundle_test_snaphot.dart';
import 'utils.dart' show generateByteList;

void main() async {
  group('DataItem:', () {
    test('create, sign, and verify data item', () async {
      final wallet = getTestWallet();
      final signer = ArweaveSigner(wallet);
      final dataItem = DataItem.withBlobData(
          owner: await wallet.getOwner(),
          data: utf8.encode('HELLOWORLD_TEST_STRING') as Uint8List)
        ..addTag('MyTag', '0')
        ..addTag('OtherTag', 'Foo')
        ..addTag('MyTag', '1');

      await dataItem.sign(signer);

      expect(await dataItem.verify(), isTrue);
    });

    test('confirm data item with wrong signaure fails verify', () async {
      final wallet = getTestWallet();
      final signer = ArweaveSigner(wallet);
      final dataItem = DataItem.withBlobData(
          owner: await wallet.getOwner(),
          data: utf8.encode('HELLOWORLD_TEST_STRING') as Uint8List)
        ..addTag('MyTag', '0')
        ..addTag('OtherTag', 'Foo')
        ..addTag('MyTag', '1');

      await dataItem.sign(signer);
      dataItem.addTag('MyTag', '2');

      expect(await dataItem.verify(), isFalse);
    });
  });

  test('create data bundle', () async {
    final wallet = getTestWallet();
    final signer = ArweaveSigner(wallet);

    final dataItemOne = DataItem.withBlobData(
        owner: await wallet.getOwner(),
        data: utf8.encode('HELLOWORLD_TEST_STRING_1') as Uint8List)
      ..addTag('MyTag', '0')
      ..addTag('OtherTag', 'Foo')
      ..addTag('MyTag', '1');
    await dataItemOne.sign(signer);
    final dataItemTwo = DataItem.withBlobData(
        owner: await wallet.getOwner(),
        data: utf8.encode('HELLOWORLD_TEST_STRING_2') as Uint8List)
      ..addTag('MyTag', '0')
      ..addTag('OtherTag', 'Foo')
      ..addTag('MyTag', '1');
    await dataItemTwo.sign(signer);
    final items = [dataItemOne, dataItemTwo];
    final bundle = await DataBundle.fromDataItems(items: items);
    expect(bundle.blob, isNotEmpty);
    for (var dataItem in items) {
      expect(await dataItem.verify(), isTrue);
    }
  });

  test('create data bundle with large files', () async {
    final wallet = getTestWallet();
    final signer = ArweaveSigner(wallet);
    final testData = generateByteList(5);

    expect(await deepHash([testData]), equals(testFileHash));

    final dataItemOne =
        DataItem.withBlobData(owner: await wallet.getOwner(), data: testData)
          ..addTag('MyTag', '0')
          ..addTag('OtherTag', 'Foo')
          ..addTag('MyTag', '1');
    await dataItemOne.sign(signer);

    final dataItemTwo =
        DataItem.withBlobData(owner: await wallet.getOwner(), data: testData)
          ..addTag('MyTag', '0')
          ..addTag('OtherTag', 'Foo')
          ..addTag('MyTag', '1');
    await dataItemTwo.sign(signer);

    final items = [dataItemOne, dataItemTwo];
    final bundle = await DataBundle.fromDataItems(items: items);
    expect(bundle.blob, isNotEmpty);

    expect(testData.length < bundle.blob.length, isTrue);
    for (var dataItem in items) {
      expect(await dataItem.verify(), isTrue);
    }
  });
}
