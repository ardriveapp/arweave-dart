@JS()
library generate_wallet;

import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:js/js.dart';

@JS()
external String generateWalletFromSeedphrase(String mnemonic);

Wallet generateWallet({required String mnemonic}) {
  final wallet = generateWalletFromSeedphrase(mnemonic);
  print(wallet);
  return Wallet.fromJwk(json.decode(wallet));
}
