import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/src/utils/graph_ql_utils.dart';
import 'package:async/async.dart';
import 'package:http/http.dart';

import 'http_client/io.dart' if (dart.library.js) 'http_client/browsers.dart';

Future<
    (
      Stream<List<int>>,
      void Function(),
    )> download({
  required String txId,
  String? gatewayHost = 'arweave.net',
  Function(double progress, int speed)? onProgress,
  bool verifyDownload = true,
}) async {
  final downloadUrl = "https://$gatewayHost/$txId";

  int bytesDownloaded = 0;
  StreamSubscription<List<int>>? subscription;
  final controller = StreamController<List<int>>();

  final txData = await _getTransactionData(
    txId: txId,
    gatewayHost: gatewayHost!,
  );

  // keep track of progress and download speed
  int lastBytes = 0;
  setProgressTimer(onProgress) => Timer.periodic(
        Duration(milliseconds: 500),
        (Timer timer) {
          double progress = double.parse(
              (bytesDownloaded / txData.dataSize).toStringAsFixed(2));
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
    final request = Request('GET', Uri.parse(downloadUrl));
    if (startByte > 0) {
      request.headers['Range'] = 'bytes=$startByte-';
    }
    final client = getClient();
    final streamResponse = await client.send(request);

    Stream<List<int>> downloadStream;

    if (verifyDownload) {
      final splitStream = StreamSplitter(streamResponse.stream);

      downloadStream = splitStream.split();
      final verificationStream = splitStream.split();

      // Calling `close()` indicates that no further streams will be created,
      // causing splitStream to function without an internal buffer.
      // The future will be completed when both streams are consumed, so we
      // shouldn't await it here.
      unawaited(splitStream.close());

      _verify(
        dataStream: verificationStream,
        txData: txData,
        txId: txId,
      ).then((isVerified) {
        if (!isVerified) {
          // TODO: maybe using a custom Exception here would be better? e.g. ValidationException
          controller.addError('failed to verify transaction');
        }

        controller.close();
        subscription?.cancel();
      });
    } else {
      /// If we don't need to verify the download, we can just return the
      /// stream directly.
      downloadStream = streamResponse.stream;
    }

    subscription = downloadStream.listen(
      (List<int> chunk) {
        bytesDownloaded += chunk.length;
        controller.sink.add(chunk);
      },
      cancelOnError: true,
      onError: (e) {
        print('[arweave]: Error downloading $txId');

        controller.addError(e);
        controller.close();

        if (onProgress != null) {
          progressTimer.cancel();
        }
      },
      onDone: () {
        if (onProgress != null) {
          progressTimer.cancel();
        }

        controller.close();
      },
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

// TODO: maybe move this to a separate file? An utils file maybe?
// We problably have the same logic on ardrive-app project. Maybe we can
// create a package with this logic and use it on both projects.
Future<TransactionData> _getTransactionData({
  required String txId,
  required String gatewayHost,
}) async {
  final gqlUrl = "https://$gatewayHost/graphql";

  final gqlResponse = await post(
    Uri.parse(gqlUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'query': gqlGetTxInfo(txId)}),
  );

  if (gqlResponse.statusCode != 200) {
    throw Exception('Failed to download $txId');
  }

  var txDataJson = jsonDecode(gqlResponse.body)['data']['transaction'];

  return TransactionData.fromJson(txDataJson);
}

Future<bool> _verify({
  required TransactionData txData,
  required String txId,
  required Stream<List<int>> dataStream,
}) {
  if (txData.isDataItem) {
    return verifyDataItem(
        id: txId,
        owner: txData.owner,
        signature: txData.signature,
        target: txData.target,
        anchor: txData.anchor,
        tags: txData.tags,
        dataStream: dataStream.map((list) => Uint8List.fromList(list)));
  } else {
    return verifyTransaction(
      id: txId,
      owner: txData.owner,
      signature: txData.signature,
      target: txData.target,
      anchor: txData.anchor,
      tags: txData.tags,
      reward: txData.reward,
      quantity: txData.quantity,
      dataSize: txData.dataSize,
      dataStream: dataStream.map((list) => Uint8List.fromList(list)),
    );
  }
}

class TransactionData {
  late String anchor;
  late String owner;
  late String target;
  late String signature;
  late int dataSize;
  late bool isDataItem;
  late int quantity;
  late int reward;
  late List<Tag> tags;

  TransactionData.fromJson(Map<String, dynamic> json) {
    parseData(json);
  }

  void parseData(Map<String, dynamic> jsonData) {
    anchor = jsonData['anchor'];
    owner = jsonData['owner']['key'];
    target = jsonData['recipient'];
    signature = jsonData['signature'];
    dataSize = int.parse(jsonData['data']['size']);
    isDataItem = jsonData['bundledIn'] != null;
    quantity = int.parse(jsonData['quantity']['winston']);
    reward = int.parse(jsonData['fee']['winston']);

    var downloadedTags = jsonData['tags'];
    tags = [];
    for (var tag in downloadedTags) {
      tags.add(createTag(tag['name'], tag['value']));
    }
  }
}
