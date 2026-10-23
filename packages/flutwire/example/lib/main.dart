import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_dio/flutwire_dio.dart';
import 'package:flutwire_http/flutwire_http.dart';
import 'package:http/http.dart' as http;

/// The whole integration is the next line. Everything below only makes calls,
/// so there is something to look at.
Future<void> main() async {
  await Flutwire.init();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutwire example',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6366F1)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        brightness: Brightness.dark,
      ),
      home: const Home(),
    );
  }
}

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Flutwire.open(context),
        icon: const Icon(Icons.cable_rounded),
        label: const Text('Open the inspector'),
      ),
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
        ],
      ),
    );
  }
}
