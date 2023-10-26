import 'dart:typed_data';

import 'package:better_cryptography/better_cryptography.dart';

import 'data_models.dart';

class SHA384Hash implements SHA384Hasher {
  late HashSink _hasher;

  @override
  init() async {
    _hasher = Sha384().newHashSink();
  }

  @override
  update(data) {
    _hasher.add(data);
  }

  @override
  hash() async {
    _hasher.close();
    return Uint8List.fromList((await _hasher.hash()).bytes);
  }
}

final _sha384 = Sha384();
Future<Uint8List> sha384(Uint8List data) async {
  return Uint8List.fromList((await _sha384.hash(data)).bytes);
}
