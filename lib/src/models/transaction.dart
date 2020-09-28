import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pointycastle/export.dart' hide Signature;

import '../crypto/crypto.dart';
import '../utils.dart';
import 'tag.dart';
import 'transaction_chunk.dart';
import 'wallet.dart';

part 'transaction.g.dart';

String _bigIntToString(BigInt v) => v.toString();
BigInt _stringToBigInt(String v) => BigInt.parse(v);

@JsonSerializable()
class Transaction {
  @JsonKey(defaultValue: 1)
  int get format => _format;
  int _format;

  String get id => _id;
  String _id;

  @JsonKey(name: 'last_tx')
  String get lastTx => _lastTx;
  String _lastTx;

  String get owner => _owner;
  String _owner;

  List<Tag> get tags => _tags;
  List<Tag> _tags;

  String get target => _target;
  String _target;

  @JsonKey(fromJson: _stringToBigInt, toJson: _bigIntToString)
  BigInt get quantity => _quantity;
  BigInt _quantity;

  /// The unencoded data associated with this transaction.
  Uint8List get data => _data;
  Uint8List _data;

  @JsonKey(name: 'data_size')
  String get dataSize => _dataSize;
  String _dataSize;

  @JsonKey(name: 'data_root')
  String get dataRoot => _dataRoot;
  String _dataRoot;

  @JsonKey(fromJson: _stringToBigInt, toJson: _bigIntToString)
  BigInt get reward => _reward;
  BigInt _reward;

  String get signature => _signature;
  String _signature;

  /// Constructs a transaction from the specified parameters.
  ///
  /// [Transaction.withStringData()] and [Transaction.withBlobData()] is the recommended way to construct data transactions.
  /// This constructor will not compute the data size or encode incoming data to Base64 for you.
  @JsonKey(ignore: true)
  TransactionChunksWithProofs get chunks => _chunks;
  TransactionChunksWithProofs _chunks;

  /// This constructor is reserved for JSON serialisation.
  /// [Transaction.withStringData()] and [Transaction.withBlobData()] are the recommended ways to construct data transactions.
  Transaction({
    int format = 2,
    String id,
    String lastTx,
    String owner,
    List<Tag> tags,
    String target = '',
    BigInt quantity,
    String data,
    Uint8List dataBytes,
    String dataSize = '0',
    String dataRoot,
    BigInt reward,
    String signature,
  })  : _format = format,
        _id = id,
        _lastTx = lastTx,
        _owner = owner,
        _tags = tags,
        _target = target,
        _quantity = quantity ?? BigInt.zero,
        _data = data != null
            ? decodeBase64ToBytes(data)
            : (dataBytes ?? Uint8List(0)),
        _dataSize = dataSize,
        _dataRoot = dataRoot ?? '',
        _reward = reward ?? BigInt.zero,
        _signature = signature {
    _tags = _tags ?? [];
  }

  /// Constructs a transaction with the specified JSON data, computed data size, and Content-Type tag.
  factory Transaction.withJsonData({
    String owner,
    List<Tag> tags,
    String target = '',
    BigInt quantity,
    Object data,
    BigInt reward,
  }) =>
      Transaction.withStringData(
        owner: owner,
        tags: tags,
        target: target,
        quantity: quantity,
        data: json.encode(data),
        reward: reward,
      )..addTag('Content-Type', 'application/json');

  /// Constructs a transaction with the specified string data and computed data size.
  factory Transaction.withStringData({
    String owner,
    List<Tag> tags,
    String target = '',
    BigInt quantity,
    String data,
    BigInt reward,
  }) =>
      Transaction.withBlobData(
        owner: owner,
        tags: tags,
        target: target,
        quantity: quantity,
        data: utf8.encode(data),
        reward: reward,
      );

  /// Constructs a transaction with the specified blob data and computed data size.
  factory Transaction.withBlobData({
    String owner,
    List<Tag> tags,
    String target = '',
    BigInt quantity,
    Uint8List data,
    BigInt reward,
  }) =>
      Transaction(
        owner: owner,
        tags: tags,
        target: target,
        quantity: quantity,
        dataBytes: data,
        dataSize: data.lengthInBytes.toString(),
        reward: reward,
      );

  void setLastTx(String lastTx) => _lastTx = lastTx;

  void setOwner(String owner) => _owner = owner;

  /// Sets the data and data size of this transaction.
  ///
  /// Also chunks and validates the incoming data for format 2 transactions.
  Future<void> setData(Uint8List data) async {
    _data = data;
    _dataSize = data.lengthInBytes.toString();

    if (format == 2) {
      final existingDataRoot = _dataRoot;
      _chunks = null;

      await prepareChunks();

      if (existingDataRoot != dataRoot) {
        throw StateError(
            'Incoming data does not match data transaction was prepared with.');
      }
    }
  }

  void setReward(BigInt reward) => _reward = reward;

  Future<void> prepareChunks() async {
    if (chunks != null) return;

    if (data.isNotEmpty) {
      _chunks = await generateTransactionChunks(data);
      _dataRoot = encodeBytesToBase64(chunks.dataRoot);
    } else {
      _chunks = TransactionChunksWithProofs(Uint8List(0), [], []);
    }
  }

  /// Returns a chunk in a format suitable for posting to /chunk.
  TransactionChunk getChunk(int index) {
    if (chunks == null) throw StateError('Chunks have not been prepared.');

    final proof = chunks.proofs[index];
    final chunk = chunks.chunks[index];

    return TransactionChunk(
      dataRoot: dataRoot,
      dataSize: dataSize,
      dataPath: encodeBytesToBase64(proof.proof),
      offset: proof.offset.toString(),
      chunk: encodeBytesToBase64(
          Uint8List.sublistView(data, chunk.minByteRange, chunk.maxByteRange)),
    );
  }

  void setSignature(String signature, String id) {
    _signature = signature;
    _id = id;
  }

  Future<Uint8List> getSignatureData() async {
    switch (format) {
      case 1:
        return Uint8List.fromList(
          decodeBase64ToBytes(owner) +
              decodeBase64ToBytes(target) +
              data +
              utf8.encode(quantity.toString()) +
              utf8.encode(reward.toString()) +
              decodeBase64ToBytes(lastTx) +
              tags
                  .expand((t) =>
                      decodeBase64ToBytes(t.name) +
                      decodeBase64ToBytes(t.value))
                  .toList(),
        );
      case 2:
        return deepHash([
          utf8.encode(format.toString()),
          decodeBase64ToBytes(owner),
          decodeBase64ToBytes(target),
          utf8.encode(quantity.toString()),
          utf8.encode(reward.toString()),
          decodeBase64ToBytes(lastTx),
          tags
              .map(
                (t) => [
                  decodeBase64ToBytes(t.name),
                  decodeBase64ToBytes(t.value),
                ],
              )
              .toList(),
          utf8.encode(dataSize),
          decodeBase64ToBytes(dataRoot),
        ]);
      default:
        throw Exception('Unexpected transaction format!');
    }
  }

  void addTag(String name, String value) {
    tags.add(
      Tag(
        encodeStringToBase64(name),
        encodeStringToBase64(value),
      ),
    );
  }

  Future<void> sign(Wallet wallet) async {
    final signatureData = await getSignatureData();
    final rawSignature = await wallet.sign(signatureData);

    final idHash = await sha256.hash(rawSignature);
    final id = encodeBytesToBase64(idHash.bytes);

    setSignature(encodeBytesToBase64(rawSignature), id);
  }

  Future<bool> verify() async {
    final signatureData = await getSignatureData();
    final claimedRawSignature = decodeBase64ToBytes(signature);

    final idHash = await sha256.hash(claimedRawSignature);
    final expectedId = encodeBytesToBase64(idHash.bytes);

    if (id != expectedId) return false;

    final ownerInt = decodeBase64ToBigInt(owner);

    try {
      final valid = await rsaPss.verify(
        signatureData,
        Signature(
          claimedRawSignature,
          publicKey: RsaJwkPublicKey(
            n: encodeBigIntToBytes(ownerInt),
            e: encodeBigIntToBytes(publicExponent),
          ),
        ),
      );

      return valid;
    } catch (err) {
      if (err is UnimplementedError) {
        var signer = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest())
          ..init(
            false,
            ParametersWithSalt(
              PublicKeyParameter<RSAPublicKey>(
                RSAPublicKey(
                  ownerInt,
                  publicExponent,
                ),
              ),
              null,
            ),
          );

        return signer.verifySignature(
            signatureData, PSSSignature(claimedRawSignature));
      } else {
        rethrow;
      }
    }
  }

  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);
  Map<String, dynamic> toJson() => _$TransactionToJson(this);
}
