import '../config.dart';
import 'preferences_web.dart';
import 'store.dart';

/// There is no disk to keep a history on in this environment, so the history
/// lives in memory. What the user picks in the settings goes to the browser's
/// own storage.
Future<FlutwireStore> openStore(
  FlutwireConfig config, {
  Future<String?> Function()? defaultPath,
}) async => MemoryFlutwireStore(
  maxCalls: config.maxCalls,
  maxBytes: config.maxMemoryBytes,
  preferences: WebFlutwirePreferences(),
);
