abstract class StreamTransactionError implements Exception {}

class DataItemCreationError extends StreamTransactionError {}

class InvalidTargetSizeError extends StreamTransactionError {}

class InvalidAnchorSizeError extends StreamTransactionError {}

class DeepHashStreamError extends StreamTransactionError {}

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
