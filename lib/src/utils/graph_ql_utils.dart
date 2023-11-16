String gqlGetTxInfo(String txId) => '''
{
  transaction(id: "$txId") {
    owner {
      key
    }
    data {
      size
    }
    quantity {
      winston
    }
    fee {
      winston
    }
    anchor
    signature
    recipient
    tags {
      name
      value
    }
    bundledIn {
      id
    }
  }
}
''';
