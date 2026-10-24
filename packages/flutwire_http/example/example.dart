import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_http/flutwire_http.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  await Flutwire.init();
  runApp(const ExampleApp());
}

/// Wrap the client your app already uses. Chopper takes it the same way, as
/// `ChopperClient(client: client)`.
final client = FlutwireClient(http.Client());

Future<void> call() async {
  try {
    await client.get(Uri.https('jsonplaceholder.typicode.com', '/todos/1'));
  } on http.ClientException {
    // Flutwire records a failed call too, so the inspector shows what happened.
  }
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: Flutwire.navigatorKey,
      // Floats the inspector button where there is no notification to tap.
      builder: Flutwire.builder,
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => unawaited(call()),
            child: const Text('Call the API'),
          ),
        ),
      ),
    );
  }
}
