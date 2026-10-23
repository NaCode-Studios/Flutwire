import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';

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
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6366F1)),
      home: const Home(),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  Future<void> _get(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      await response.drain<void>();
    } on Exception {
      // The inspector shows failures; the demo does not need to.
    } finally {
      client.close();
    }
  }

  Future<void> _post(String url, Object body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close();
      await response.drain<void>();
    } on Exception {
      // As above.
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutwire example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: () =>
                _get('https://jsonplaceholder.typicode.com/todos/1'),
            child: const Text('GET a JSON todo'),
          ),
          FilledButton(
            onPressed: () => _post(
              'https://jsonplaceholder.typicode.com/posts',
              {'title': 'hello', 'body': 'from Flutwire', 'userId': 1},
            ),
            child: const Text('POST a post'),
          ),
          FilledButton(
            onPressed: () => _get('https://httpbin.org/status/500'),
            child: const Text('GET a 500'),
          ),
          FilledButton(
            onPressed: () => _get('https://nonexistent.invalid/'),
            child: const Text('GET a host that does not exist'),
          ),
          OutlinedButton(
            onPressed: () => Flutwire.open(context),
            child: const Text('Open the inspector'),
          ),
        ],
      ),
    );
  }
}
