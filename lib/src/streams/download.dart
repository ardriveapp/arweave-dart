import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:arweave/arweave.dart';
import 'package:async/async.dart';
import 'package:http/http.dart' as http;

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

Future<
    (
      Stream<List<int>>,
      void Function(),
    )> download({
  required String txId,
  String? gatewayHost = 'arweave.net',
  Function(double progress, int speed)? onProgress,
}) async {
  final downloadUrl = "https://$gatewayHost/$txId";
  final gqlUrl = "https://$gatewayHost/graphql";
  final client = http.Client();
  final gqlResponse = await http.post(
    Uri.parse(gqlUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'query': gqlGetTxInfo(txId)}),
  );

  if (gqlResponse.statusCode != 200) {
    throw Exception('Failed to download $txId');
  }

  var txData = jsonDecode(gqlResponse.body)['data']['transaction'];

  final txAnchor = txData['anchor'];
  final txOwner = txData['owner']['key'];
  final txTarget = txData['recipient'];
  final txSignature = txData['signature'];
  final txDataSize = int.parse(txData['data']['size']);
  final isDataItem = txData['bundledIn'] != null;
  final txQuantity = int.parse(txData['quantity']['winston']);
  final txReward = int.parse(txData['fee']['winston']);
  final downloadedTags = txData['tags'];
  final List<Tag> txTags = [];
  for (var tag in downloadedTags) {
    txTags.add(createTag(tag['name'], tag['value']));
  }

  int bytesDownloaded = 0;
  StreamSubscription<List<int>>? subscription;
  final controller = StreamController<List<int>>();

  // keep track of progress and download speed
  int lastBytes = 0;
  setProgressTimer(onProgress) => Timer.periodic(
        Duration(milliseconds: 500),
        (Timer timer) {
          double progress =
              double.parse((bytesDownloaded / txDataSize).toStringAsFixed(2));
          int speed = bytesDownloaded - lastBytes;

          onProgress(
              progress, speed * 2); // multiply by 2 to get bytes per second

          lastBytes = bytesDownloaded;
        },
      );

  late Timer progressTimer;

  Future<void> startDownload([int startByte = 0]) async {
    if (onProgress != null) {
      progressTimer = setProgressTimer(onProgress);
    }
    final request = http.Request('GET', Uri.parse(downloadUrl));
    if (startByte > 0) {
      request.headers['Range'] = 'bytes=$startByte-';
    }
    final streamResponse = await client.send(request);

    final splitStream = StreamSplitter(streamResponse.stream);
    final downloadStream = splitStream.split();
    final verificationStream = splitStream.split();

    // Calling `close()` indicates that no further streams will be created,
    // causing splitStream to function without an internal buffer.
    // The future will be completed when both streams are consumed, so we
    // shouldn't await it here.
    unawaited(splitStream.close());

    _verify(
      isDataItem: isDataItem,
      id: txId,
      owner: txOwner,
      signature: txSignature,
      target: txTarget,
      anchor: txAnchor,
      tags: txTags,
      dataStream: verificationStream.map((list) => Uint8List.fromList(list)),
      reward: txReward,
      quantity: txQuantity,
      dataSize: txDataSize,
    ).then((isVerified) {
      if (!isVerified) {
        controller.addError('failed to verify transaction');
      }

      subscription?.cancel();
      controller.close();
      if (onProgress != null) {
        progressTimer.cancel();
      }
    });

    subscription = downloadStream.listen(
      (List<int> chunk) {
        bytesDownloaded += chunk.length;
        controller.sink.add(chunk);
      },
      cancelOnError: true,
    );
  }

  // TODO: expose pause and resume after implementing them for verification
  // void pauseDownload() {
  //   subscription?.cancel();
  //   if (onProgress != null) {
  //     progressTimer.cancel();
  //   }
  // }
  //
  // void resumeDownload() {
  //   startDownload(bytesDownloaded);
  // }

  void cancelDownload() {
    controller.addError('download cancelled');
    subscription?.cancel();
    controller.close();
    if (onProgress != null) {
      progressTimer.cancel();
    }
  }

  startDownload();

  return (controller.stream, cancelDownload);
}

_verify({
  required bool isDataItem,
  required String id,
  required String owner,
  required String signature,
  required String target,
  required String anchor,
  required List<Tag> tags,
  required Stream<List<int>> dataStream,
  required int reward,
  required int quantity,
  required int dataSize,
}) {
  if (isDataItem) {
    return verifyDataItem(
        id: id,
        owner: owner,
        signature: signature,
        target: target,
        anchor: anchor,
        tags: tags,
        dataStream: dataStream.map((list) => Uint8List.fromList(list)));
  } else {
    return verifyTransaction(
      id: id,
      owner: owner,
      signature: signature,
      target: target,
      anchor: anchor,
      tags: tags,
      reward: reward,
      quantity: quantity,
      dataSize: dataSize,
      dataStream: dataStream.map((list) => Uint8List.fromList(list)),
    );
  }
}
