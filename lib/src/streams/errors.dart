abstract class DataItemError implements Exception {}

class DataItemCreationError extends DataItemError {}

class InvalidTargetSizeError extends DataItemError {}

class InvalidAnchorSizeError extends DataItemError {}

class DeepHashStreamError extends DataItemError {}

class SignatureError extends DataItemError {}

class GetWalletOwnerError extends DataItemError {}

class ProcessedDataItemHeadersError extends DataItemError {}

class DecodeBase64ToBytesError extends DataItemError {}

class SerializeTagsError extends DataItemError {}

abstract class TransactionError implements Exception {}

class GenerateTransactionChunksError extends TransactionError {}

class PrepareChunksError extends TransactionError {}

class TransactionDeepHashError extends TransactionError {}

class TransactionSignatureError extends TransactionError {}

class TransactionGetOwnerError extends TransactionError {}
