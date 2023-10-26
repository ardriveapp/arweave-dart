import 'package:http/http.dart';
import 'package:fetch_client/fetch_client.dart';

Client getClient() => FetchClient(
      mode: RequestMode.cors,
      // streamRequests: true,
    );
