
import 'api/api.dart';
import 'chunks.dart';
import 'transactions.dart';

class Arweave {
  ArweaveApi get api => _api;
  late ArweaveApi _api;

  ArweaveTransactionsApi get transactions => _transactions;
  late ArweaveTransactionsApi _transactions;

  ArweaveChunksApi get chunks => _chunks;
  late ArweaveChunksApi _chunks;

  Arweave({
    required ArweaveApi api,
  }) : _api = api {
    _transactions = ArweaveTransactionsApi(this.api);
    _chunks = ArweaveChunksApi(this.api);
  }
}
