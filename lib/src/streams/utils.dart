import 'dart:async';
import 'dart:typed_data';

String toBase64Url(String base64) {
  return base64.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

Stream<List<int>> toStream(data) {
  return Stream.fromIterable([data]);
}

int decodeBytesToLong(Uint8List list) {
  int value = 0;

  for (int i = list.length - 1; i >= 0; i--) {
    value = value * 256 + list[i];
  }

  return value;
}

Future<List<Stream<List<int>>>> getStreams(
    List<Future<(String, int, Future<Stream<List<int>>> Function())> Function()>
        functions) async {
  List<Stream<List<int>>> result = [];

  for (var function in functions) {
    var futureTuple = await function();
    var futureStreamFunction = futureTuple.$3;
    var stream = await futureStreamFunction();
    result.add(stream);
  }

  return result;
}

Stream<List<int>> byteRangeStream(
    Stream<List<int>> stream, int start, int end) async* {
  int currentBytePosition = 0;

  await for (List<int> chunk in stream) {
    int chunkStart = 0;
    int chunkEnd = chunk.length;

    if (currentBytePosition + chunk.length < start) {
      currentBytePosition += chunk.length;
      continue;
    }

    if (currentBytePosition < start) {
      chunkStart = start - currentBytePosition;
    }

    if (currentBytePosition + chunk.length > end) {
      chunkEnd = end - currentBytePosition + 1;
    }

    yield chunk.sublist(chunkStart, chunkEnd);

    currentBytePosition += chunk.length;

    if (currentBytePosition > end) {
      break;
    }
  }
}

Stream<List<int>> concatenateStreams(List<Stream<List<int>>> streams) async* {
  for (var stream in streams) {
    yield* stream;
  }
}
