import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

Future<Uint8List> deepHash(dynamic data) async {
  if (data is Stream<List<int>>) {
    final hasher = AccumulatorSink<Digest>();
    final input = sha384.startChunkedConversion(hasher);

    int length = 0;

    await for (final chunk in data) {
      length += chunk.length;
      input.add(chunk);
    }
    input.close();

    final Digest digest = hasher.events.single;

    final tag =
        stringToUint8List('blob') + stringToUint8List(length.toString());

    final taggedHash = sha384Hash(tag) + digest.bytes;

    return sha384Hash(taggedHash);
  } else if (data is List<List> || data is List<Stream<List<int>>>) {
    final tag =
        stringToUint8List('list') + stringToUint8List(data.length.toString());

    return await deepHashChunks(data, sha384Hash(tag));
  }

  final Uint8List _data = data as Uint8List;

  final tag = stringToUint8List('blob') +
      stringToUint8List(_data.lengthInBytes.toString());

  final taggedHash = sha384Hash(tag) + sha384Hash(_data);

  return sha384Hash(taggedHash);
}

Future<Uint8List> deepHashChunks(dynamic chunks, Uint8List acc) async {
  if (chunks.isEmpty) {
    return acc;
  }

  final hashPair = acc + await deepHash(chunks[0]);
  final newAcc = sha384Hash(hashPair);

  return await deepHashChunks(
      chunks.length == 1 ? [] : chunks.sublist(1), newAcc);
}

Uint8List stringToUint8List(String string) {
  return Uint8List.fromList(utf8.encode(string));
}

Uint8List sha384Hash(List<int> data) {
  return Uint8List.fromList(sha384.convert(data).bytes);
}
