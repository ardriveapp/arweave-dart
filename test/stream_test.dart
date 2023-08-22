import 'dart:io';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/stream.dart';
import 'package:arweave/utils.dart';

final File dataItemStream = File('./test/fixtures/bundle');

void main() async {
  var wallet = await Wallet.generate();

  final file = File('./file.mp4');

  Future<Stream<List<int>>> streamGenerator() async {
    return file.openRead();
  }

  final tags = [
    Tag(
      encodeStringToBase64('App-Name'),
      encodeStringToBase64('ArDrive-App'),
    ),
    Tag(
      encodeStringToBase64('App-Platform'),
      encodeStringToBase64('Web'),
    ),
    Tag(
      encodeStringToBase64('App-Version'),
      encodeStringToBase64('2.4.1'),
    ),
    Tag(
      encodeStringToBase64('Unix-Time'),
      encodeStringToBase64('1688749775'),
    ),
    Tag(
      encodeStringToBase64('Content-Type'),
      encodeStringToBase64('video/mp4'),
    ),
  ];

  dataItemGenerator() async {
    return await createDataItem(
        wallet: wallet,
        tags: tags,
        dataStreamGenerator: streamGenerator,
        dataSize: file.lengthSync());
  }

  bdiGenerator() async {
    return await createBdi(
        wallet: wallet, dataItemsGenerator: [dataItemGenerator]);
  }
}
