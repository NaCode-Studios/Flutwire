import 'strings.dart';

/// Italian.
class FlutwireStringsIt extends FlutwireStrings {
  /// Creates the Italian strings.
  const FlutwireStringsIt();

  @override
  String get channelName => 'Attività di rete';

  @override
  String get channelDescription =>
      'Un riepilogo delle chiamate HTTP fatte dall\'app.';

  @override
  String get notificationTitle => 'Registrazione attività di rete';

  @override
  String get clear => 'Cancella';

  @override
  String get shortcutLabel => 'Apri Flutwire';

  @override
  String summary({required int calls, required int failed}) {
    final base = calls == 1 ? '1 chiamata' : '$calls chiamate';
    if (failed == 0) return base;
    return failed == 1
        ? '$base · 1 non riuscita'
        : '$base · $failed non riuscite';
  }
}
