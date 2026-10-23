import 'strings.dart';

/// English.
class FlutwireStringsEn extends FlutwireStrings {
  /// Creates the English strings.
  const FlutwireStringsEn();

  @override
  String get channelName => 'Network activity';

  @override
  String get channelDescription =>
      'A summary of the HTTP calls your app makes.';

  @override
  String get notificationTitle => 'Recording network activity';

  @override
  String get clear => 'Clear';

  @override
  String get shortcutLabel => 'Open Flutwire';

  @override
  String summary({required int calls, required int failed}) {
    final base = calls == 1 ? '1 call' : '$calls calls';
    return failed == 0 ? base : '$base · $failed failed';
  }
}
