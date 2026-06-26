import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionData.fromJson', () {
    Map<String, dynamic> baseJson() => {
          'owner': {'key': 'owner-key'},
          'data': {'size': '174771'},
          'quantity': {'winston': '0'},
          'fee': {'winston': '0'},
          'anchor': 'an-anchor',
          'signature': 'a-signature',
          'recipient': 'a-recipient',
          'tags': [
            {'name': 'Content-Type', 'value': 'application/pdf'},
          ],
          'bundledIn': {'id': 'bundle-id'},
        };

    test('parses a fully-populated transaction', () {
      final data = TransactionData.fromJson(baseJson());

      expect(data.owner, 'owner-key');
      expect(data.dataSize, 174771);
      expect(data.anchor, 'an-anchor');
      expect(data.signature, 'a-signature');
      expect(data.target, 'a-recipient');
      expect(data.isDataItem, isTrue);
      expect(data.tags, hasLength(1));
    });

    test('coalesces null anchor/recipient/signature to empty strings', () {
      // Gateways return `null` (not `''`) for absent optional fields. Before
      // the fix this threw `type 'JSNull' is not a subtype of type 'String'`
      // on web.
      final json = baseJson()
        ..['anchor'] = null
        ..['recipient'] = null
        ..['signature'] = null;

      final data = TransactionData.fromJson(json);

      expect(data.anchor, '');
      expect(data.target, '');
      expect(data.signature, '');
    });

    test('treats a null tags list as empty', () {
      final json = baseJson()..['tags'] = null;

      final data = TransactionData.fromJson(json);

      expect(data.tags, isEmpty);
    });

    test('isDataItem is false when bundledIn is null', () {
      final json = baseJson()..['bundledIn'] = null;

      final data = TransactionData.fromJson(json);

      expect(data.isDataItem, isFalse);
    });

    test('round-trips a real gateway response with null anchor', () {
      // Shape returned by turbo-gateway.com for a bundled data item.
      const body =
          '{"data":{"transaction":{"owner":{"key":"owner-key"},'
          '"data":{"size":"174771"},"quantity":{"winston":"0"},'
          '"fee":{"winston":"0"},"anchor":null,"signature":"sig",'
          '"recipient":"","bundledIn":{"id":"bundle-id"},"tags":[]}}}';

      final txJson = jsonDecode(body)['data']['transaction'];
      final data = TransactionData.fromJson(txJson);

      expect(data.anchor, '');
      expect(data.target, '');
      expect(data.isDataItem, isTrue);
      expect(data.dataSize, 174771);
    });
  });
}
