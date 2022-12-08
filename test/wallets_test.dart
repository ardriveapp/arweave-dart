import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('wallets:', () {
    test('decode and encode wallet', () async {
      final jwk =
          json.decode(await File('test/fixtures/test-key.json').readAsString());
      expect(Wallet.fromJwk(jwk).toJwk(), equals(jwk));
    }, onPlatform: {
      'browser': Skip('dart:io unavailable'),
    });

    test('decode and encode old wallet', () async {
      // Older wallets have a slightly different format to the latest ones.
      // Make sure we can decode them.
      Map<String, dynamic> jwk = json
          .decode(await File('test/fixtures/test-key-old.json').readAsString());

      // The `ext` field is irrelevant to the actual key so we can afford
      // to lose it when encoding back out.
      expect(Wallet.fromJwk(jwk).toJwk(), equals(jwk..remove('ext')));
    }, onPlatform: {
      'browser': Skip('dart:io unavailable'),
    });

    final jwkFieldPattern = RegExp(r'^[a-z0-9-_]{683}$', caseSensitive: false);
    test('generate wallet', () async {
      final walletA = await Wallet.generate();
      final walletB = await Wallet.generate();

      final walletJwk = walletA.toJwk();
      expect(walletJwk['kty'], equals('RSA'));
      expect(walletJwk['e'], equals('AQAB'));

      expect(walletJwk['n'], matches(jwkFieldPattern));
      expect(walletJwk['d'], matches(jwkFieldPattern));

      expect(await walletA.getAddress(), matches(digestPattern));
      expect(await walletB.getAddress(), matches(digestPattern));

      expect(await walletA.getAddress(),
          isNot(equals(await walletB.getAddress())));
    });

    test('resolve address from wallet', () async {
      final wallet = await getTestWallet();
      expect(await wallet.getAddress(),
          equals('fOVzBRTBnyt4VrUUYadBH8yras_-jhgpmNgg-5b3vEw'));
    }, onPlatform: {
      'browser': Skip('dart:io unavailable'),
    });

    test('sign message with wallet', () async {
      final wallet = await getTestWallet();
      final message = utf8.encode('<test message>');

      final signature = await wallet.sign(message as Uint8List);
      expect(
        utils.encodeBytesToBase64(signature),
        startsWith('II5LxGnPt4WTSz9P__wMAdjzXWlZE-wGbKU7wm4DbGuPXB5Vifs'),
      );
    }, onPlatform: {
      'browser': Skip('dart:io unavailable'),
    });

    test('generates a mnemonic with the expected word count', () async {
      String mnemonic = Wallet().generateMnemonics();

      expect(mnemonic.split(" ").length, 12);
    });

    test('generate a wallet from mnemonics', () async {
      const String mnemonics =
          'shrimp pony traffic photo favorite plastic fancy gadget february surge surface innocent';

      Uint8List seed = Wallet().generateSeedFromMnemonics(mnemonics);

      var wallet = await Wallet.generate(seed: seed);
      expect(
        await wallet.getAddress(),
        '0nYC9uPt61tUhVKH_rqbGLmfA5zPP1Vv263nDSyxzds',
      );
    });
  });
}
