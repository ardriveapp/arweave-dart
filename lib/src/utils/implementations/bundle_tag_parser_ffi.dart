import 'dart:typed_data';

import 'package:arweave/arweave.dart';

import '../../utils.dart';

/// ONLY FOR TESTING. WILL NOT PASS BUNDLE VERIFICATION
Uint8List serializeTags({required List<Tag> tags}) {
  // TODO: Add avro implementation
  // This serialzation is onlt meant for testing.
  // Any bundles created with this will not verify as this is not in the avro schema
  return Uint8List.fromList(tags
      .expand((t) => decodeBase64ToBytes(t.name) + decodeBase64ToBytes(t.value))
      .toList());
}
