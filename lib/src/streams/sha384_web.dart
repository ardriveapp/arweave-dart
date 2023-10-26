@JS('SHA384')
library SHA384;

import 'dart:html';
import 'dart:js_util';
import 'dart:typed_data';
import 'dart:async';

import 'package:js/js.dart';

import 'data_models.dart';

@JS()
@anonymous
class IHasher {
  external IHasher init();
  external IHasher update(Uint8List data);
  external dynamic digest(String outputType);
  external dynamic save();
  external IHasher load(dynamic data);
  external int get blockSize;
  external int get digestSize;
}

@JS('createSHA384')
external Future<IHasher> _createSHA384();

Future<IHasher> createSHA384() async {
  return await promiseToFuture(_createSHA384());
}

@JS('sha384Hash')
external Future<String> _sha384Hash(Uint8List data);

class SHA384Hash implements SHA384Hasher {
  late IHasher _hasher;

  @override
  init() async {
    _hasher = await promiseToFuture(_createSHA384());
  }

  @override
  update(data) {
    _hasher.update(data);
  }

  @override
  hash() async {
    return Uint8List.fromList(_hasher.digest('binary'));
  }
}

Future<Uint8List> sha384(Uint8List data) async {
  return await promiseToFuture(_sha384Hash(data));
}
