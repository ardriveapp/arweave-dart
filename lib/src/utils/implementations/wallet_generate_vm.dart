import 'package:arweave/arweave.dart';
import 'package:arweave/src/utils/hmac_drbg.dart';
import 'package:arweave/utils.dart';
import 'package:bip39/bip39.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hash/hash.dart';
import 'package:pointycastle/export.dart';

Future<Wallet> generateWallet({required String mnemonic}) async {
  SecureRandom secureRandom;

  secureRandom = HmacDRBG(entropy: mnemonicToSeed(mnemonic), hash: SHA256());

  final keyGen = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(
          publicExponent,
          keyLength,
          64,
        ),
        secureRandom,
      ),
    );

  final pair = keyGen.generateKeyPair();

  final privK = pair.privateKey as RSAPrivateKey;

  return Wallet(
    keyPair: RsaKeyPairData(
      e: encodeBigIntToBytes(privK.publicExponent!),
      n: encodeBigIntToBytes(privK.modulus!),
      d: encodeBigIntToBytes(privK.privateExponent!),
      p: encodeBigIntToBytes(privK.p!),
      q: encodeBigIntToBytes(privK.q!),
    ),
  );
}
