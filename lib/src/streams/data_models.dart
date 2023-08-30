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

typedef DataStreamGenerator = Stream<List<int>> Function();
typedef DataItemTaskEither = TaskEither<DataItemError, DataItemResult>;

class DataItemResult {
  final String id;
  final int size;
  final DataStreamGenerator stream;

  const DataItemResult({
    required this.id,
    required this.size,
    required this.stream,
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

typedef DataBundleTaskEither = TaskEither<DataItemError, DataBundleResult>;

class DataBundleResult {
  final int size;
  final DataStreamGenerator stream;

  const DataBundleResult({
    required this.size,
    required this.stream,
  });
}
