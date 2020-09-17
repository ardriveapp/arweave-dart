import 'dart:convert';

import 'package:arweave/arweave.dart';

void main() async {
  // Initialise an Arweave client.
  final client = Arweave();

  // Load an Arweave wallet.
  final wallet = Wallet.fromJwk(json.decode('<wallet jwk>'));

  // Create a data transaction.
  final transaction = await client.transactions.prepare(
    Transaction.withStringData(data: 'Hello world!'),
    wallet,
  );

  // Optionally add tags to the transaction.
  transaction.addTag('App-Name', 'Hello World App');
  transaction.addTag('App-Version', '1.0.0');

  // Sign the transaction.
  await transaction.sign(wallet);

  // Upload the transaction in a single call:
  await client.transactions.post(transaction);

  // Or for larger data transactions, upload it progressively:
  await for (final upload in client.transactions.upload(transaction)) {
    print('${upload.percentageComplete}%');
  }
}
