import 'dart:typed_data';

import 'package:arweave/arweave.dart';

abstract class Signer {
  SignatureConfig get signatureConfig;
  Future<Uint8List> sign(Uint8List message);
}

class ArweaveSigner implements Signer {
  final Wallet wallet;

  ArweaveSigner(this.wallet);

  @override
  SignatureConfig get signatureConfig => SignatureConfig.arweave;

  @override
  Future<Uint8List> sign(Uint8List message) {
    return wallet.sign(message);
  }
}
