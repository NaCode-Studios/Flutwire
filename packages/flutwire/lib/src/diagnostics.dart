import 'dart:developer' as developer;

/// Says that Flutwire met a problem it dealt with, so a developer can find out
/// why something is missing from the inspector.
///
/// It goes to the logging view of DevTools and to the console of `flutter run`
/// under the name `Flutwire`, and it never throws. The app never sees it.
void reportProblem(String message, {Object? error, StackTrace? stack}) {
  developer.log(
    message,
    name: 'Flutwire',
    level: _warning,
    error: error,
    stackTrace: stack,
  );
}

/// The level `package:logging` calls a warning.
const int _warning = 900;
