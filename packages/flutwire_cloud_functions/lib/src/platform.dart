import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';

import 'recording.dart';

/// The Cloud Functions platform with Flutwire in the middle: every callable it
/// hands out calls the real one and records what went in and what came out.
class FlutwireFunctionsPlatform extends FirebaseFunctionsPlatform {
  /// Wraps [inner], the platform the plugin was using.
  FlutwireFunctionsPlatform(
    FirebaseFunctionsPlatform inner, {
    String? projectId,
    FirebaseApp? app,
    String? region,
  }) : _inner = inner,
       _projectId = projectId,
       super(app, region ?? inner.region);

  final FirebaseFunctionsPlatform _inner;
  final String? _projectId;

  @override
  FirebaseFunctionsPlatform delegateFor({
    FirebaseApp? app,
    required String region,
  }) => FlutwireFunctionsPlatform(
    _inner.delegateFor(app: app, region: region),
    projectId: _projectId,
    app: app,
    region: region,
  );

  @override
  HttpsCallablePlatform httpsCallable(
    String? origin,
    String name,
    HttpsCallableOptions options,
  ) => FlutwireCallable(
    this,
    _inner.httpsCallable(origin, name, options),
    origin: origin,
    name: name,
    options: options,
  );

  @override
  HttpsCallablePlatform httpsCallableWithUri(
    String? origin,
    Uri uri,
    HttpsCallableOptions options,
  ) => FlutwireCallable(
    this,
    _inner.httpsCallableWithUri(origin, uri, options),
    origin: origin,
    uri: uri,
    options: options,
  );

  /// The project id the URLs are written with.
  String get projectId =>
      _projectId ?? app?.options.projectId ?? 'unknown-project';
}

/// A callable function that records each call before and after it reaches the
/// real one.
class FlutwireCallable extends HttpsCallablePlatform {
  /// Wraps [inner], the callable the plugin created.
  FlutwireCallable(
    FlutwireFunctionsPlatform functions,
    HttpsCallablePlatform inner, {
    String? origin,
    String? name,
    Uri? uri,
    required HttpsCallableOptions options,
  }) : _inner = inner,
       _functions = functions,
       super(functions, origin, name, options, uri);

  final HttpsCallablePlatform _inner;
  final FlutwireFunctionsPlatform _functions;

  /// The address the call goes to, as the Firebase SDK builds it.
  Uri get endpoint {
    final fixed = uri;
    if (fixed != null) return fixed;
    final project = _functions.projectId;
    final region = _functions.region;
    final local = origin;
    if (local != null && local.isNotEmpty) {
      return Uri.parse('$local/$project/$region/$name');
    }
    return Uri.https('$region-$project.cloudfunctions.net', '/$name');
  }

  @override
  Future<dynamic> call([dynamic parameters]) async {
    final recording = Recording.start(endpoint, parameters);
    // The app may have changed the options since this callable was made.
    _inner.options = options;
    try {
      final result = await _inner.call(parameters);
      recording?.succeeded(result);
      return result;
    } catch (error, stack) {
      recording?.failed(error, stack);
      rethrow;
    }
  }

  @override
  Stream<dynamic> stream(Object? parameters) async* {
    final recording = Recording.start(endpoint, parameters);
    _inner.options = options;
    var finished = false;
    try {
      await for (final event in _inner.stream(parameters)) {
        recording?.event(event);
        yield event;
      }
      finished = true;
      recording?.streamEnded();
    } catch (error, stack) {
      finished = true;
      recording?.failed(error, stack);
      rethrow;
    } finally {
      // The listener went away before the stream finished.
      if (!finished) recording?.cancelled();
    }
  }
}
