import 'dart:typed_data';

import 'package:arweave/arweave.dart';

abstract class Signer {
  SignatureConfig get signatureConfig;
  Future<Uint8List> sign(Uint8List message, [String? context]);
}

class ArweaveSigner implements Signer {
  final Wallet wallet;
  final String? context;

  ArweaveSigner(this.wallet, {this.context});

  @override
  SignatureConfig get signatureConfig => SignatureConfig.arweave;

  @override
  Future<Uint8List> sign(Uint8List message, [String? signContext]) {
    // Use the signContext if provided, otherwise fall back to the signer's context
    return wallet.sign(message, signContext ?? context);
  }
}
