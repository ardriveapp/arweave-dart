import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import 'errors.dart';

class SignDataItemResult {
  final String id;
  final Uint8List signature;

  const SignDataItemResult({
    required this.id,
    required this.signature,
  });
}

typedef DataStreamGenerator = Stream<Uint8List> Function();
typedef DataItemTaskEither = TaskEither<StreamTransactionError, DataItemResult>;

class DataItemResult {
  final String id;
  final int dataItemSize;
  final int dataSize;
  final DataStreamGenerator streamGenerator;

  const DataItemResult({
    required this.id,
    required this.dataItemSize,
    required this.dataSize,
    required this.streamGenerator,
  });
}

class ProcessedDataItem {
  final String id;
  final String signature;
  final String owner;
  final String target;
  final String anchor;
  final List<int> tags;
  final int dataLength;
  final DataStreamGenerator dataStreamGenerator;

  const ProcessedDataItem({
    required this.id,
    required this.signature,
    required this.owner,
    required this.target,
    required this.anchor,
    required this.tags,
    required this.dataLength,
    required this.dataStreamGenerator,
  });
}

typedef DataBundleTaskEither
    = TaskEither<StreamTransactionError, DataBundleResult>;

class DataBundleResult {
  final int dataBundleStreamSize;
  final int dataItemsSize;
  final DataStreamGenerator stream;

  const DataBundleResult({
    required this.dataBundleStreamSize,
    required this.dataItemsSize,
    required this.stream,
  });
}

abstract class SHA384Hasher {
  Future<void> init();
  void update(Uint8List data);
  Future<Uint8List> hash();
}
