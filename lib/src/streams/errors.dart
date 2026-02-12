abstract class StreamTransactionError implements Exception {}

class DataItemCreationError extends StreamTransactionError {}

class InvalidTargetSizeError extends StreamTransactionError {}

class InvalidAnchorSizeError extends StreamTransactionError {}

class DeepHashStreamError extends StreamTransactionError {}

class DeepHashError extends StreamTransactionError {}

class SignatureError extends StreamTransactionError {}

class GetWalletOwnerError extends StreamTransactionError {}

class ProcessedDataItemHeadersError extends StreamTransactionError {}

class DecodeBase64ToBytesError extends StreamTransactionError {}

class SerializeTagsError extends StreamTransactionError {}

class GenerateTransactionChunksError extends StreamTransactionError {}

class PrepareChunksError extends StreamTransactionError {}

class TransactionDeepHashError extends StreamTransactionError {}

class TransactionSignatureError extends StreamTransactionError {}

class TransactionGetOwnerError extends StreamTransactionError {}

class GetTxAnchorError extends StreamTransactionError {}

class GetTxPriceError extends StreamTransactionError {}

/// Thrown when anchor or price must be fetched from the network but no gateway
/// [ArweaveApi] was provided. Pass [arweave] into [createTransactionTaskEither]
/// so tx_anchor and price requests use your configured gateway instead of the
/// default (arweave.net).
class GatewayNotConfiguredError extends StreamTransactionError {}

class PostTxHeadersError extends StreamTransactionError {}

class PostTxChunksError extends StreamTransactionError {}
