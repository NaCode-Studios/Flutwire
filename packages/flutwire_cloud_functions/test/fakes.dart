import 'dart:async';

import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

typedef Handler = FutureOr<dynamic> Function(Object? parameters);
typedef Events = Stream<dynamic> Function(Object? parameters);

class FakeException extends FirebaseFunctionsException {
  FakeException(String code, String message, {super.details})
    : super(code: code, message: message);
}

/// Stands in for the plugin: answers from [handler] instead of the native SDK.
class FakeFunctions extends FirebaseFunctionsPlatform {
  FakeFunctions(this.handler, {this.events, String region = 'us-central1'})
    : super(null, region);

  final Handler handler;
  final Events? events;

  @override
  FirebaseFunctionsPlatform delegateFor({
    FirebaseApp? app,
    required String region,
  }) => FakeFunctions(handler, events: events, region: region);

  @override
  HttpsCallablePlatform httpsCallable(
    String? origin,
    String name,
    HttpsCallableOptions options,
  ) => FakeCallable(this, origin, name, options, null);

  @override
  HttpsCallablePlatform httpsCallableWithUri(
    String? origin,
    Uri uri,
    HttpsCallableOptions options,
  ) => FakeCallable(this, origin, null, options, uri);
}

class FakeCallable extends HttpsCallablePlatform {
  FakeCallable(
    FakeFunctions super.functions,
    super.origin,
    super.name,
    super.options,
    super.uri,
  );

  FakeFunctions get fake => functions as FakeFunctions;

  @override
  Future<dynamic> call([Object? parameters]) async => fake.handler(parameters);

  @override
  Stream<dynamic> stream(Object? parameters) => fake.events!(parameters);
}
