import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_dio/flutwire_dio.dart';

Future<void> main() async {
  await Flutwire.init();
  runApp(const ExampleApp());
}

/// Add the interceptor last, so that it sees the headers the others added.
final dio = Dio()..interceptors.add(FlutwireDioInterceptor());

Future<void> call() async {
  try {
    await dio.get<Object?>('https://jsonplaceholder.typicode.com/todos/1');
  } on DioException {
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
