import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<Uint8List> deepHash(dynamic data) async {
  if (data is Stream<List<int>>) {
    final sink = Sha384().newHashSink();

    int length = 0;

    await for (final chunk in data) {
      length += chunk.length;
      sink.add(chunk);
    }
    sink.close();

    final tag =
        stringToUint8List('blob') + stringToUint8List(length.toString());

    final taggedHash = await sha384Hash(tag) + (await sink.hash()).bytes;

    return sha384Hash(taggedHash);
  } else if (data is List<List> || data is List<Stream<List<int>>>) {
    final tag =
        stringToUint8List('list') + stringToUint8List(data.length.toString());

    return await deepHashChunks(data, await sha384Hash(tag));
  }

  final Uint8List _data = data as Uint8List;

  final tag = stringToUint8List('blob') +
      stringToUint8List(_data.lengthInBytes.toString());

  final taggedHash = await sha384Hash(tag) + await sha384Hash(_data);

  return await sha384Hash(taggedHash);
}

Future<Uint8List> deepHashChunks(dynamic chunks, Uint8List acc) async {
  if (chunks.isEmpty) {
    return acc;
  }

  final hashPair = acc + await deepHash(chunks[0]);
  final newAcc = await sha384Hash(hashPair);

  return await deepHashChunks(
      chunks.length == 1 ? [] : chunks.sublist(1), newAcc);
}

Uint8List stringToUint8List(String string) {
  return Uint8List.fromList(utf8.encode(string));
}

final sha384 = Sha384();

Future<Uint8List> sha384Hash(List<int> data) async {
  return Uint8List.fromList((await sha384.hash(data)).bytes);
}
