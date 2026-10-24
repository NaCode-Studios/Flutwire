import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutwire/flutwire.dart';
import 'package:flutwire_cloud_functions/flutwire_cloud_functions.dart';

Future<void> main() async {
  await Firebase.initializeApp();
  await Flutwire.init();
  // Before the first call: an instance of FirebaseFunctions that already
  // exists keeps talking to the plugin directly.
  FlutwireCloudFunctions.install();
  runApp(const ExampleApp());
}

Future<void> call() async {
  try {
    await FirebaseFunctions.instance.httpsCallable('greet').call<Object?>({
      'name': 'Ada',
    });
  } on FirebaseFunctionsException {
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
            child: const Text('Call the function'),
          ),
        ),
      ),
    );
  }
}
