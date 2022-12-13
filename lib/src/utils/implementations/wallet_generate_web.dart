@JS()
library generate_wallet;

import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS()
external dynamic generateWalletFromSeedphrase(String mnemonic);

Future<Wallet> generateWallet({required String mnemonic}) async {
  final wallet = await promiseToFuture(generateWalletFromSeedphrase(mnemonic));
  print(wallet);
  return Wallet.fromJwk(json.decode(wallet));
}
