import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'crypto/crypto.dart';

final keyLength = 4096;
final publicExponent = BigInt.from(65537);

Uint8List decodeBase64ToBytes(String base64) =>
    base64Url.decode(base64Url.normalize(base64));

String decodeBase64ToString(String base64) =>
    utf8.decode(decodeBase64ToBytes(base64));

BigInt decodeBase64ToBigInt(String base64) =>
    decodeBytesToBigInt(decodeBase64ToBytes(base64));

BigInt decodeBytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;

  for (var i = 0; i < bytes.length; i++) {
    result += BigInt.from(bytes[bytes.length - i - 1]) << (8 * i);
  }
  return result;
}

String decodeStringFromBase64(String base64String) {
  var paddingLength = 4 - base64String.length % 4;
  var paddedBase64String =
      paddingLength != 4 ? base64String + ('=' * paddingLength) : base64String;
  return utf8.decode(base64Url.decode(paddedBase64String));
}

String encodeStringToBase64(String string) =>
    encodeBytesToBase64(utf8.encode(string));

String encodeBytesToBase64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

final _byteMask = BigInt.from(0xff);
Uint8List encodeBigIntToBytes(BigInt bigInt) {
  var size = (bigInt.bitLength + 7) >> 3;
  var result = Uint8List(size);
  for (var i = 0; i < size; i++) {
    result[size - i - 1] = (bigInt & _byteMask).toInt();
    bigInt = bigInt >> 8;
  }
  return result;
}

String encodeBigIntToBase64(BigInt bigInt) =>
    encodeBytesToBase64(encodeBigIntToBytes(bigInt));

BigInt arToWinston(String ar) {
  if (ar.startsWith('.') || ar.endsWith('.')) {
    throw ArgumentError('AR format is invalid.');
  }

  if (ar.contains('.')) {
    final decimalPoint = ar.lastIndexOf('.');
    ar = ar.substring(0, decimalPoint) +
        ar.substring(decimalPoint + 1, ar.length).padRight(12, '0');
  } else {
    // If the string does not contain a decimal point the AR value is at least 1.
    ar = ar + '000000000000';
  }

  return BigInt.parse(ar);
}

String winstonToAr(BigInt winston) {
  var bit = winston.toString().padLeft(12, '0');

  // The Winston amount is less than 1 AR.
  if (bit.length == 12) {
    bit = '0.' + bit;
  } else {
    bit = bit.substring(0, bit.length - 12) +
        '.' +
        bit.substring(bit.length - 12, bit.length);
  }

  // Trim trailing zeroes.
  while (bit.endsWith('0')) {
    bit = bit.substring(0, bit.length - 1);

    if (bit.endsWith('.')) {
      bit = bit.substring(0, bit.length - 1);
      break;
    }
  }

  return bit;
}

/// True when the response is a 400 with multi-peer results (e.g. tx header not
/// yet propagated). These should be retried with backoff.
bool isChunkPropagationRetriableResponse(int statusCode, String body) {
  if (statusCode != 400) return false;
  try {
    final map = json.decode(body) as Map<String, dynamic>;
    final results = map['results'];
    if (results is! List || results.isEmpty) return false;
    final successCount = map['successCount'];
    if (successCount is int && successCount > 0) return false;
    return true;
  } catch (_) {
    return false;
  }
}

/// Safely get the error from an Arweave HTTP response.
String getResponseError(http.Response res) {
  if (res.headers['Content-Type'] == 'application/json') {
    Map<String, dynamic> errJson = json.decode(res.body);

    if (errJson['data'] != null) {
      return errJson['data'] is Map
          ? errJson['data']['error']
          : errJson['data'];
    }
  }

  return res.body;
}

/// The error a node or gateway gave in a Dio response, as a string.
///
/// Never throws: the chunk uploader calls it to decide whether to retry, and
/// a throw here escapes the retry entirely, failing the upload after its
/// header was already posted. Dio has usually decoded a JSON body into a Map
/// already, so [Response.data] may be a Map, a List, a String or null. An
/// Arweave node answers `{"error": "data_root_not_found"}`, the legacy shape
/// is `{"data": {"error": ...}}`, and an AR.IO gateway answers with its
/// broadcast result, which has no error string and is returned whole.
String getResponseErrorFromDioRespose(Response res) {
  try {
    var data = res.data;
    if (data is String) {
      try {
        data = json.decode(data);
      } catch (_) {
        return data as String;
      }
    }
    if (data is Map) {
      final error = data['error'];
      if (error is String) return error;
      final nested = data['data'];
      if (nested is Map && nested['error'] is String) {
        return nested['error'] as String;
      }
      if (nested is String) return nested;
    }
    return data == null ? '' : json.encode(data);
  } catch (_) {
    return '${res.data}';
  }
}

Future<String> ownerToAddress(String owner) async => encodeBytesToBase64(
    await sha256.hash(decodeBase64ToBytes(owner)).then((res) => res.bytes));

Uint8List longTo32ByteArray(int long) {
  // we want to represent the input as a 8-bytes array
  final byteArray = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  for (var index = 0; index < byteArray.length; index++) {
    final byte = long & 0xff;
    byteArray[index] = byte;
    long = (long - byte) ~/ 256;
  }

  return Uint8List.fromList(byteArray);
}

Uint8List shortTo2ByteArray(int long) {
  if (long > (2 ^ (32 - 1))) throw Exception('Short too long');

  var byteArray = [0, 0];

  for (var index = 0; index < byteArray.length; index++) {
    final byte = long & 0xff;
    byteArray[index] = byte;
    long = (long - byte) ~/ 256;
  }

  return Uint8List.fromList(byteArray);
}

int byteArrayToLong(Uint8List byteArray) {
  var value = 0;
  for (var i = byteArray.length - 1; i >= 0; i--) {
    value = value * 256 + byteArray[i];
  }
  return value;
}

Uint8List longTo8ByteArray(int long) {
  // we want to represent the input as a 8-bytes array
  final byteArray = [0, 0, 0, 0, 0, 0, 0, 0];

  for (var index = 0; index < byteArray.length; index++) {
    final byte = long & 0xff;
    byteArray[index] = byte;
    long = (long - byte) ~/ 256;
  }

  return Uint8List.fromList(byteArray);
}
