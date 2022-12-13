import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';

import 'package:arweave/src/utils/wallet_generate.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:jwk/jwk.dart';

import '../crypto/crypto.dart';
import '../utils.dart';

class Wallet {
  RsaKeyPair? _keyPair;
  Wallet({KeyPair? keyPair}) : _keyPair = keyPair as RsaKeyPair?;

  static Future<Wallet> generate({String? mnemonic}) async {
    return generateWallet(
      mnemonic: mnemonic ?? bip39.generateMnemonic(),
    );
  }

  String generateMnemonics() => bip39.generateMnemonic();

  Uint8List generateSeedFromMnemonics(String mnemonics) =>
      bip39.mnemonicToSeed(mnemonics);

  Future<String> getOwner() async => encodeBytesToBase64(
      await _keyPair!.extractPublicKey().then((res) => res.n));
  Future<String> getAddress() async => ownerToAddress(await getOwner());

  Future<Uint8List> sign(Uint8List message) async =>
      rsaPssSign(message: message, keyPair: _keyPair!);

  factory Wallet.fromJwk(Map<String, dynamic> jwk) {
    // Normalize the JWK so that it can be decoded by 'cryptography'.
    jwk = jwk.map((key, value) {
      if (key == 'kty' || value is! String) {
        return MapEntry(key, value);
      } else {
        return MapEntry(key, base64Url.normalize(value));
      }
    });

    return Wallet(keyPair: Jwk.fromJson(jwk).toKeyPair());
  }

  Map<String, dynamic> toJwk() => Jwk.fromKeyPair(_keyPair!).toJson().map(
      // Denormalize the JWK into the expected form.
      (key, value) => MapEntry(key, (value as String).replaceAll('=', '')));
}
