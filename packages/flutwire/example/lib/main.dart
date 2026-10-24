import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_dio/flutwire_dio.dart';
import 'package:flutwire_http/flutwire_http.dart';
import 'package:http/http.dart' as http;

/// The whole integration is the next line, and `interception` is the one
/// option it turns on, so that a mock or a breakpoint can be tried on the calls
/// below. Everything below only makes calls, so there is something to look at.
Future<void> main() async {
  await Flutwire.init(config: const FlutwireConfig(interception: true));
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutwire example',
      navigatorKey: Flutwire.navigatorKey,
      // Floats the inspector button where there is no notification to tap.
      builder: Flutwire.builder,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF546E7A)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF546E7A),
        brightness: Brightness.dark,
      ),
      home: const Home(),
    );
  }
}

/// Whether the platform has a notification that opens the inspector.
bool get _hasNotification =>
    !kIsWeb &&
    const {
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }.contains(defaultTargetPlatform);

/// One button of the demo: a label and the call it makes.
class Probe {
  const Probe(this.label, this.run);

  final String label;
  final Future<void> Function() run;
}

const _bin = 'https://httpbin.org';
const _todos = 'https://jsonplaceholder.typicode.com';

// On mobile and desktop the adapters below stand down, because Flutwire already
// records every dart:io call. On the web they are what records the calls.
final dio = Dio()..interceptors.add(FlutwireDioInterceptor());
final client = FlutwireClient(http.Client());

Future<void> _io(String method, String url, {Object? json}) async {
  if (kIsWeb) return _safe(() => client.get(Uri.parse(url)));
  final io = HttpClient();
  try {
    final request = await io.openUrl(method, Uri.parse(url));
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    await response.drain<void>();
  } on Object {
    // The inspector shows what went wrong.
  } finally {
    io.close();
  }
}

Future<void> _safe(Future<Object?> Function() call) async {
  try {
    await call();
  } on Object {
    // As above.
  }
}

final List<(String, List<Probe>)> groups = [
  (
    'dart:io, http and Dio',
    [
      Probe('dart:io GET', () => _io('GET', '$_todos/todos/1')),
      Probe(
        'http GET',
        () => _safe(() => client.get(Uri.parse('$_todos/users/1'))),
      ),
      Probe('Dio GET', () => _safe(() => dio.get<Object?>('$_todos/posts/1'))),
      Probe(
        'http POST JSON',
        () => _safe(
          () => client.post(
            Uri.parse('$_todos/posts'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer example-token',
            },
            body: jsonEncode({
              'title': 'hello',
              'body': 'from Flutwire',
              'userId': 1,
            }),
          ),
        ),
      ),
      Probe(
        'Dio POST form',
        () => _safe(
          () => dio.post<Object?>(
            '$_bin/post',
            data: {'name': 'Ada', 'password': 'hunter2'},
            options: Options(contentType: Headers.formUrlEncodedContentType),
          ),
        ),
      ),
      Probe(
        'Dio multipart',
        () => _safe(
          () => dio.post<Object?>(
            '$_bin/post',
            data: FormData.fromMap({
              'caption': 'a small upload',
              'file': MultipartFile.fromBytes(
                List.generate(2048, (i) => i % 251),
                filename: 'bytes.bin',
              ),
            }),
          ),
        ),
      ),
      Probe(
        'GraphQL query',
        () => _safe(
          () => client.post(
            Uri.parse('https://countries.trevorblades.com/graphql'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'operationName': 'Countries',
              'query': 'query Countries { countries { code name emoji } }',
            }),
          ),
        ),
      ),
    ],
  ),
  (
    'Bodies',
    [
      Probe('JSON', () => _safe(() => client.get(Uri.parse('$_bin/json')))),
      Probe('XML', () => _safe(() => client.get(Uri.parse('$_bin/xml')))),
      Probe('HTML', () => _safe(() => client.get(Uri.parse('$_bin/html')))),
      Probe(
        'Image (PNG)',
        () => _safe(() => client.get(Uri.parse('$_bin/image/png'))),
      ),
      Probe(
        'Binary',
        () => _safe(() => client.get(Uri.parse('$_bin/bytes/4096'))),
      ),
      Probe('Gzip', () => _safe(() => client.get(Uri.parse('$_bin/gzip')))),
      Probe(
        'Big JSON',
        () => _safe(() => client.get(Uri.parse('$_bin/stream/60'))),
      ),
      Probe(
        'Cookies',
        () => _safe(
          () =>
              client.get(Uri.parse('$_bin/cookies/set?theme=dark&session=abc')),
        ),
      ),
      Probe('MessagePack', () => _canned(_messagePack, 'application/msgpack')),
      Probe('Protobuf', () => _canned(_protobuf, 'application/x-protobuf')),
    ],
  ),
  (
    'Streams',
    [Probe('WebSocket', _webSocket), Probe('Event stream', _eventStream)],
  ),
  (
    'Isolates',
    [
      Probe('Flutwire.run', () => _safe(() => Flutwire.run(_runInAnIsolate))),
      Probe(
        'Flutwire.compute',
        () => _safe(() => Flutwire.compute(_fetchIn, '$_todos/todos/5')),
      ),
    ],
  ),
  (
    'Trouble',
    [
      Probe(
        'Redirects',
        () => _safe(() => client.get(Uri.parse('$_bin/redirect/2'))),
      ),
      Probe(
        '404',
        () => _safe(() => client.get(Uri.parse('$_bin/status/404'))),
      ),
      Probe(
        '500',
        () => _safe(() => client.get(Uri.parse('$_bin/status/500'))),
      ),
      Probe(
        'Slow (6 s)',
        () => _safe(() => client.get(Uri.parse('$_bin/delay/6'))),
      ),
      Probe('Unknown host', () => _io('GET', 'https://nonexistent.invalid/')),
      Probe(
        'Timeout',
        () => _safe(
          () => dio.get<Object?>(
            '$_bin/delay/8',
            options: Options(receiveTimeout: const Duration(seconds: 1)),
          ),
        ),
      ),
    ],
  ),
];

/// `{"club": "Orion", "members": 3, "tags": ["a", "b"], "founded": 1999.5}`.
const List<int> _messagePack = [
  0x84, //
  0xa4, 0x63, 0x6c, 0x75, 0x62, 0xa5, 0x4f, 0x72, 0x69, 0x6f, 0x6e,
  0xa7, 0x6d, 0x65, 0x6d, 0x62, 0x65, 0x72, 0x73, 0x03,
  0xa4, 0x74, 0x61, 0x67, 0x73, 0x92, 0xa1, 0x61, 0xa1, 0x62,
  0xa7, 0x66, 0x6f, 0x75, 0x6e, 0x64, 0x65, 0x64,
  0xcb, 0x40, 0x9f, 0x3e, 0x00, 0x00, 0x00, 0x00, 0x00,
];

/// A message of field 1 as "Orion", field 2 as 3 and field 3 as a message of
/// its own that holds "Vega" in field 1.
const List<int> _protobuf = [
  0x0a, 0x05, 0x4f, 0x72, 0x69, 0x6f, 0x6e, //
  0x10, 0x03,
  0x1a, 0x06, 0x0a, 0x04, 0x56, 0x65, 0x67, 0x61,
];

/// Answers with [body] and the media type [type], so that the viewer has
/// something to decode. The client records the call itself.
Future<void> _canned(List<int> body, String type) => _safe(
  () => FlutwireClient(
    _Canned(body, type),
    force: true,
  ).get(Uri.parse('$_todos/club')),
);

/// Opens a WebSocket to an echo server, sends a text and a binary message, and
/// closes it, so the inspector has a conversation to list. `dart:io` makes one
/// client for every WebSocket the first time it opens one, so this works
/// because `Flutwire.init` ran before that.
Future<void> _webSocket() async {
  if (kIsWeb) return;
  try {
    final socket = await WebSocket.connect('wss://echo.websocket.org');
    final closed = Completer<void>();
    socket.listen(
      (_) {},
      onDone: closed.complete,
      onError: (Object _) => closed.complete(),
    );
    socket
      ..add('hello')
      ..add(jsonEncode({'subscribe': 'prices'}))
      ..add(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(const Duration(seconds: 2));
    await socket.close(1000, 'done');
    await closed.future.timeout(const Duration(seconds: 5));
  } on Object {
    // The inspector shows what went wrong.
  }
}

/// Reads a few chunks of a public event stream and walks away, so the
/// inspector lists the events that arrived and the call ends as cancelled.
Future<void> _eventStream() async {
  if (kIsWeb) return;
  final io = HttpClient();
  try {
    final request = await io.getUrl(
      Uri.parse('https://stream.wikimedia.org/v2/stream/recentchange'),
    );
    request.headers.set('accept', 'text/event-stream');
    final response = await request.close();
    await response
        .transform(utf8.decoder)
        .take(6)
        .drain<void>()
        .timeout(const Duration(seconds: 10));
  } on Object {
    // The inspector shows what went wrong.
  } finally {
    io.close(force: true);
  }
}

/// A call made in an isolate that `Flutwire.run` attached to Flutwire, so it is
/// in the history like any other.
Future<void> _runInAnIsolate() => _fetchIn('$_todos/todos/4');

/// The same through `Flutwire.compute`, which hands the callback one message.
Future<void> _fetchIn(String url) async {
  if (kIsWeb) return _safe(() => client.get(Uri.parse(url)));
  final io = HttpClient();
  try {
    final request = await io.getUrl(Uri.parse(url));
    await (await request.close()).drain<void>();
  } on Object {
    // The inspector shows what went wrong.
  } finally {
    io.close();
  }
}

/// What Flutwire cannot see, so that the inspector has something to say about
/// it. These are left out of "Run everything": replacing the capture stops the
/// recording of everything after it.
final List<Probe> blindSpots = [
  Probe(
    'Isolate, not attached',
    () => _safe(() => Isolate.run(_fromAnotherIsolate)),
  ),
  Probe(
    'Off the wire',
    () => _safe(
      () => FlutwireClient(_OffTheWire()).get(Uri.parse('$_todos/todos/3')),
    ),
  ),
  Probe('Replace the capture', () async {
    _kept ??= HttpOverrides.current;
    HttpOverrides.global = _Replacing();
  }),
  Probe('Restore the capture', () async => HttpOverrides.global = _kept),
];

HttpOverrides? _kept;

/// A call from an isolate that never attached to Flutwire. Overrides belong to
/// one isolate, so nothing records it, and the inspector says so.
Future<void> _fromAnotherIsolate() async {
  try {
    await FlutwireClient(http.Client()).get(Uri.parse('$_todos/todos/2'));
  } on Object {
    // The point is the note in the inspector, not the answer.
  }
}

/// A client that answers every request with the same body.
class _Canned extends http.BaseClient {
  _Canned(this.body, this.type);

  final List<int> body;
  final String type;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(body),
        200,
        headers: {'content-type': type},
      );
}

/// A client with a transport of its own, as `cronet_http` has: it never
/// reaches dart:io, so the capture cannot see what it sends.
class _OffTheWire extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode('{"from":"a client that is off the wire"}')),
        200,
        headers: {'content-type': 'application/json'},
      );
}

/// Overrides that know nothing of Flutwire's, as an app's own do when it sets
/// them after `Flutwire.init` and does not chain to what was there.
class _Replacing extends HttpOverrides {}

class Home extends StatelessWidget {
  const Home({super.key});

  Future<void> _runAll() async {
    for (final group in groups) {
      for (final probe in group.$2) {
        unawaited(probe.run());
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Flutwire example')),
      // Where there is no notification Flutwire floats a button of its own in
      // this corner, so the example adds none.
      floatingActionButton: _hasNotification
          ? FloatingActionButton.extended(
              onPressed: () => Flutwire.open(context),
              icon: const Icon(Icons.cable_rounded),
              label: const Text('Open the inspector'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(
            'Make some calls, then open the inspector, or pull down the notification shade.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _runAll,
            child: const Text('Run everything'),
          ),
          for (final group in groups) ...[
            const SizedBox(height: 20),
            Text(
              group.$1,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final probe in group.$2)
                  OutlinedButton(
                    onPressed: () => unawaited(probe.run()),
                    child: Text(probe.label),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Blind spots',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final probe in blindSpots)
                OutlinedButton(
                  onPressed: () => unawaited(probe.run()),
                  child: Text(probe.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
