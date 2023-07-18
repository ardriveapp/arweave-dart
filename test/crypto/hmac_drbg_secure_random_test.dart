import 'dart:typed_data';

import 'package:arweave/src/crypto/hmac_drbg_secure_random.dart';
import 'package:bip39/bip39.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  test('HmacDrbgSecureRandom returns same bytes from 1-filled seed as JS',
      () async {
    final seed = Uint8List.fromList(List<int>.generate(64, (i) => 1));
    final secureRandom = HmacDrbgSecureRandom();

    secureRandom.seed(KeyParameter(seed));

    final bytes = secureRandom.nextBytes(8);

    const expected = [34, 199, 111, 231, 149, 69, 120, 221];
    expect(bytes, equals(Uint8List.fromList(expected)));
  }, onPlatform: {
    'browser': Skip('dart:io unavailable'),
  });

  test('HmacDrbgSecureRandom returns same bytes from seed as JS', () async {
    final testArweaveAppWalletMnemonic =
        "child collect expose tunnel youth response idle suspect accuse drink clip athlete";
    final seed = mnemonicToSeed(testArweaveAppWalletMnemonic);
    final secureRandom = HmacDrbgSecureRandom();
    secureRandom.seed(KeyParameter(seed));

    final bytes = secureRandom.nextBytes(8);

    const expected = [3, 141, 196, 54, 177, 78, 115, 59];
    expect(bytes, equals(Uint8List.fromList(expected)));
  }, onPlatform: {
    'browser': Skip('dart:io unavailable'),
  });
}
