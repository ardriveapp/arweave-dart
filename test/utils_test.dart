import 'dart:typed_data';

import 'package:arweave/src/utils.dart';
import 'package:arweave/src/utils/hmac_drbg.dart';
import 'package:bip39/bip39.dart';
import 'package:hash/hash.dart';
import 'package:test/test.dart';

typedef SandboxDomain = String;
typedef TxId = String;
void main() async {
  group('Utils:', () {
    test('longTo8ByteArray', () async {
      var long = 9;
      expect(longTo8ByteArray(long), [9, 0, 0, 0, 0, 0, 0, 0]);
    });

    String encodeHEX(List<int> bytes) {
      var str = '';
      for (var i = 0; i < bytes.length; i++) {
        var s = bytes[i].toRadixString(16);

        str += s.padLeft(2, '0');
      }
      return str;
    }

    group('Hmac_DRBG', () {
      test('should support hmac-drbg-sha256', () {
        final Uint8List input = Uint8List.fromList([
          0,
          154,
          249,
          204,
          74,
          252,
          96,
          17,
          99,
          69,
          171,
          150,
          78,
          3,
          10,
          56,
          41,
          180,
          204,
          17,
          31,
          122,
          5,
          3,
          129,
          43,
          27,
          182,
          42,
          194,
          102,
          195,
          120,
          71,
          29,
          185,
          12,
          118,
          247,
          240,
          225,
          86,
          101,
          157,
          173,
          142,
          55,
          24,
          11,
          141,
          164,
          127,
          156,
          124,
          83,
          139,
          123,
          13,
          79,
          132,
          106,
          107,
          98,
          29
        ]);
        final Uint8List expected = Uint8List.fromList([
          53,
          222,
          72,
          231,
          29,
          212,
          203,
          45,
          255,
          198,
          184,
          36,
          227,
          159,
          147,
          155,
          166,
          239,
          198,
          231,
          85,
          70,
          11,
          167,
          89,
          144,
          191,
          134,
          206,
          101,
          54,
          180
        ]);

        var drbg = HmacDRBG(
          hash: SHA256(),
          outLen: 256,
          entropy: input,
        );

        print(encodeHEX(expected));
        expect(drbg.generate(32), expected);
      });

      test('output using 1-filled seed matches JS output', () {
        final Uint8List expected =
            Uint8List.fromList([34, 199, 111, 231, 149, 69, 120, 221]);

        final seed = Uint8List.fromList(List<int>.generate(64, (i) => 1));

        var drbg = HmacDRBG(
            hash: SHA256(),
            outLen: 256,
            entropy: seed,
            nonce: null,
            pers: null);

        expect(drbg.generate(8), expected);
      });

      test('output using test mnemonic matches JS output', () {
        final Uint8List expected =
            Uint8List.fromList([3, 141, 196, 54, 177, 78, 115, 59]);

        final testArweaveAppWalletMnemonic =
            "child collect expose tunnel youth response idle suspect accuse drink clip athlete";
        final seed = mnemonicToSeed(testArweaveAppWalletMnemonic);

        var drbg = HmacDRBG(
            hash: SHA256(),
            outLen: 256,
            entropy: seed,
            nonce: null,
            pers: null);

        expect(drbg.generate(8), expected);
      });
    });

    test('output on successive calls matches JS output', () {
      final expected = [
        Uint8List.fromList([3, 141, 196, 54]),
        Uint8List.fromList([254, 185, 98, 54]),
        Uint8List.fromList([162, 28, 90, 78]),
      ];

      final testArweaveAppWalletMnemonic =
          "child collect expose tunnel youth response idle suspect accuse drink clip athlete";
      final seed = mnemonicToSeed(testArweaveAppWalletMnemonic);

      var drbg = HmacDRBG(
          hash: SHA256(), outLen: 256, entropy: seed, nonce: null, pers: null);

      for (final res in expected) {
        expect(drbg.generate(4), equals(res));
      }
    });

  });
}
