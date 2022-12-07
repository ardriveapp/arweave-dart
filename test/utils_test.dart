import 'dart:typed_data';

import 'package:arweave/src/api/sandbox.dart';
import 'package:arweave/src/utils.dart';
import 'package:arweave/src/utils/hmac_drbg.dart';
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
    });

    test('Sandbox Domain Generation test', () {
      Map<SandboxDomain, TxId> testBaseline = {
        'f3valm4d36fd6w4uhuibvjrnwra3entolqiojhlcsghhnp32pstq':
            'LuoFs4Pfij9blD0QGqYttEGyNm5cEOSdYpGOdr96fKc',
        'flqlektwzxrgtlpmce53dnnej2clq5njgbbh2tztjbs4aqz3owjq':
            'KuCyKnbN4mmt7BE7sbWkToS4dakwQn1PM0hlwEM7dZM',
        '6c6fodlctydufzmbsmzykkweigtk5w5zrqauiyetmcaqukgm':
            '8LxXDWKeB_0LlgZMzhSrEQaau27-mMAURgk2CBCijMY',
        'oerew5mrlsda5yrsmml3vwpxb6tvpobbzyfb4l5pucthyyhmbe':
            'cSJLdZFchg7iMmMXutn3D6dXuCHOCh4_vr6CmfGDsCc',
        'vxxdwy6scapybz7ekkw32ua5naseioagnu4uutbq3cftvivl':
            're47Y9IQH4-Dn5FKtvVAdaCRE-OAZtOUpMMNiLOqKrw',
        'bujjxactpuy7cmm3ul6fjuwuqnbymloddqvsjswhxsvkd255bq':
            'DRKbgFN9MfExm6L8VNLUg0OGLcMcKyTKx7yq_oeu9DM',
        'b4zy2sx2upeczfaxpscxfuglgh2mljo4gu6ycuhujgz5yjbc':
            'DzONSvqjyCyUF3yFctDLMfTFpd_w-1PYFQ9Emz3CQic',
        'kruhyqr3j24gxknxda2pbqa6ru2ctocctwr4z3hesnjukreb':
            'VGh8QjtOuGuptxg08MAejTQpuEKdo8zs_5JNTRUSB_Q',
      };

      testBaseline.forEach(
          (key, value) => expect(key, equals(toB32(fromB64Url(value)))));
    });
  });
}
