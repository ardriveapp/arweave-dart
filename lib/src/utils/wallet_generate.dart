import 'package:arweave/arweave.dart';

import 'implementations/wallet_generate_web.dart'
    if (dart.library.io) 'implementations/wallet_generate_vm.dart'
    as implementation;

Wallet generateWallet({required String seed}) =>
    implementation.generateWallet(mnemonic: seed);
