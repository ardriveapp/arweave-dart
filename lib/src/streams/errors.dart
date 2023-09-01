abstract class DataItemError {}

class DataItemCreationError extends DataItemError {}

class InvalidTargetSizeError extends DataItemError {}

class InvalidAnchorSizeError extends DataItemError {}

class DataItemDeepHashError extends DataItemError {}

class SignatureError extends DataItemError {}

class GetWalletOwnerError extends DataItemError {}

class ProcessedDataItemHeadersError extends DataItemError {}

class DecodeBase64ToBytesError extends DataItemError {}

class SerializeTagsError extends DataItemError {}

abstract class TransactionError {}

class GenerateTransactionChunksError extends TransactionError {}

class PrepareChunksError extends TransactionError {}

class TransactionDeepHashError extends TransactionError {}

class TransactionSignatureError extends TransactionError {}

class TransactionGetOwnerError extends TransactionError {}
