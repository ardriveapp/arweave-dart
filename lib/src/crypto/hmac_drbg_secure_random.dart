import 'dart:typed_data';

import 'package:hash/hash.dart';
import 'package:pointycastle/export.dart';

import '../utils.dart';
import '../utils/hmac_drbg.dart';

class HmacDrbgSecureRandom implements SecureRandom {
  HmacDRBG _hmacDRBG;

  HmacDrbgSecureRandom()
      : _hmacDRBG = HmacDRBG(
            hash: SHA256(),
            entropy: Uint8List.fromList([0]),
            nonce: null,
            pers: null,
            outLen: 256);

  @override
  String get algorithmName => 'HmacDrgbSecureRandom';

  @override
  BigInt nextBigInteger(int bitLength) {
    // This was made to match jsbn.js's behavior of generating 1 extra byte
    // and zeroing out the first byte. Generating 1 extra byte then trimming the
    // first byte here is equivalent in behavior.
    var bytes = nextBytes(bitLength ~/ 8 + 1);
    return decodeBytesToBigInt(bytes.sublist(1, bitLength ~/ 8 + 1));
  }

  @override
  Uint8List nextBytes(int count) {
    final res = _hmacDRBG.generate(count);
    return res;
  }

  @override
  int nextUint16() {
    var byteData = nextBytes(2).buffer.asByteData();
    return byteData.getUint16(0);
  }

  @override
  int nextUint32() {
    var byteData = nextBytes(4).buffer.asByteData();
    return byteData.getUint32(0);
  }

  @override
  int nextUint8() {
    var byteData = nextBytes(1).buffer.asByteData();
    return byteData.getUint8(0);
  }

  @override
  void seed(covariant KeyParameter params) {
    _hmacDRBG = HmacDRBG(
        hash: SHA256(),
        entropy: params.key,
        nonce: null,
        pers: null,
        outLen: 256);
  }
}
