library hmac_drgb;

import 'dart:typed_data';

import 'package:hash/hash.dart' as h;
import 'package:pointycastle/pointycastle.dart';

abstract class ByteBasedSecureRandom implements SecureRandom {
  @override
  BigInt nextBigInteger(int bitLength) {
    int byteCount = (bitLength + 7) ~/ 8;
    Uint8List bytes = nextBytes(byteCount);
    String s = '';
    for (int i = 0; i < byteCount; i++) {
      s = s + (bytes[i].toRadixString(2).padLeft(8, '0'));
    }
    return BigInt.parse(s, radix: 2).toUnsigned(bitLength);
  }

  @override
  int nextUint16() {
    return nextBytes(2).buffer.asByteData().getUint16(0);
  }

  @override
  int nextUint32() {
    return nextBytes(4).buffer.asByteData().getUint32(0);
  }

  @override
  int nextUint8() {
    return nextBytes(1).buffer.asByteData().getUint8(0);
  }

  @override
  void seed(CipherParameters params) {}
}

class HmacDRBG extends ByteBasedSecureRandom {
  h.BlockHash hash;
  bool? predResist;

  late int outSize;
  late Uint8List K;
  late Uint8List V;

  HmacDRBG({
    required this.hash,
    this.predResist,
    int outLen = 0,
    int? minEntropy,
    required Uint8List entropy,
    Uint8List? nonce,
    Uint8List? pers,
  }) {
    outSize = outLen;
    _init(entropy, nonce ?? Uint8List(0), pers ?? Uint8List(0));
  }
  void _init(Uint8List entropy, Uint8List nonce, Uint8List pers) {
    var seed = Uint8List(entropy.length + nonce.length + pers.length);
    var offset = 0;
    var end = entropy.length;
    seed.setRange(offset, end, entropy);
    offset = end;
    end += nonce.length;
    seed.setRange(offset, end, nonce);
    offset = end;
    end += pers.length;
    seed.setRange(offset, end, pers);

    K = Uint8List(outSize ~/ 8);
    V = Uint8List(outSize ~/ 8);
    for (var i = 0; i < V.length; i++) {
      K[i] = 0x00;
      V[i] = 0x01;
    }

    _update(seed);
  }

  h.Hmac _hmac() {
    return h.Hmac(hash, K);
  }

  void _update(Uint8List seed) {
    var kmac = _hmac().update(V).update([0x00]);
    kmac = kmac.update(seed);

    K = kmac.digest();
    V = _hmac().update(V).digest();

    K = _hmac().update(V).update([0x01]).update(seed).digest();
    V = _hmac().update(V).digest();
  }

  Uint8List generate(int len, [Uint8List? add]) {
    // Optional additional data
    if (add != null) {
      _update(add);
    }

    var temp = <int>[];
    while (temp.length < len) {
      V = _hmac().update(V).digest();
      temp.addAll(V);
    }

    var res = temp.sublist(0, len);

    return Uint8List.fromList(res);
  }

  @override
  String get algorithmName => 'HmacDRBG';

  @override
  Uint8List nextBytes(int count) {
    return generate(count);
  }

  @override
  void seed(CipherParameters params) {}
}
