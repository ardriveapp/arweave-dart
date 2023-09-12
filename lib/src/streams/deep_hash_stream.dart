import 'dart:convert';
import 'dart:typed_data';

import 'sha384_io.dart' if (dart.library.js) 'sha384_web.dart';

Future<Uint8List> deepHashStream(dynamic data) async {
  if (data is Stream<Uint8List>) {
    final hasher = SHA384Hash();
    await hasher.init();

    int length = 0;

    await for (final chunk in data) {
      length += chunk.length;
      hasher.update(chunk);
    }

    final tag = concatenateUint8Lists(
        stringToUint8List('blob'), stringToUint8List(length.toString()));

    final taggedHash =
        concatenateUint8Lists(await sha384(tag), await hasher.hash());

    return await sha384(taggedHash);
  } else if (data is List<List> || data is List<Stream<Uint8List>>) {
    final tag = concatenateUint8Lists(
        stringToUint8List('list'), stringToUint8List(data.length.toString()));

    return await deepHashChunks(data, await sha384(tag));
  } else {
    throw FormatException('Invalid data type.');
  }
}

Future<Uint8List> deepHashChunks(dynamic chunks, Uint8List acc) async {
  if (chunks.isEmpty) {
    return acc;
  }

  final hashPair = concatenateUint8Lists(acc, await deepHashStream(chunks[0]));
  final newAcc = await sha384(hashPair);

  return await deepHashChunks(
      chunks.length == 1 ? [] : chunks.sublist(1), newAcc);
}

Uint8List stringToUint8List(String string) {
  return Uint8List.fromList(utf8.encode(string));
}

Uint8List concatenateUint8Lists(Uint8List a, Uint8List b) {
  final builder = BytesBuilder(copy: false);

  builder.add(a);
  builder.add(b);

  return builder.takeBytes();
}
