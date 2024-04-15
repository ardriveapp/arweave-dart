import 'dart:typed_data';

import 'package:arweave/src/crypto/crypto.dart';
import 'package:arweave/utils.dart';

typedef Verifier = Future<bool> Function(
    Uint8List message, Uint8List signature, String owner);

class SignatureConfig {
  final String signatureName;
  final int signatureType;
  final int signatureLength;
  final int publicKeyLength; // OWNER
  final Verifier verify;

  const SignatureConfig(this.signatureName, this.signatureType,
      this.signatureLength, this.publicKeyLength, this.verify);

  /// owner corresponds to base64 representation of public key
  static final SignatureConfig arweave = SignatureConfig('arweave', 1, 512, 512,
      (Uint8List message, Uint8List signature, String owner) {
    final publicExponent = BigInt.from(65537);
    return rsaPssVerify(
      input: message,
      signature: signature,
      modulus: decodeBase64ToBigInt(owner),
      publicExponent: publicExponent,
    );
  });

  static final SignatureConfig ed25519 = SignatureConfig('ed25519', 2, 64, 32,
      (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });

  static final SignatureConfig ethereum = SignatureConfig('ethereum', 3, 65, 65,
      (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });

  static final SignatureConfig solana = SignatureConfig('solana', 4, 64, 32,
      (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });

  static final SignatureConfig injectedAptos =
      SignatureConfig('injectedAptos', 5, 64, 32,
          (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });

  ///  signatureLength: max 32 64 byte signatures, +4 for 32-bit bitmap
  ///  publicKeyLength: max 64 32 byte keys, +1 for 8-bit threshold value
  static final SignatureConfig multiAptos =
      SignatureConfig('multiAptos', 6, 64 * 32 + 4, 32 * 32 + 1,
          (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });

  static final SignatureConfig typedEthereum =
      SignatureConfig('typedEthereum', 7, 65, 42,
          (Uint8List message, Uint8List signature, String owner) {
    throw UnimplementedError();
  });
}
