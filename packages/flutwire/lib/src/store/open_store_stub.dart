import '../config.dart';
import 'store.dart';

/// There is no disk to keep a history on in this environment, so the history
/// lives in memory.
Future<FlutwireStore> openStore(
  FlutwireConfig config, {
  Future<String?> Function()? defaultPath,
}) async => MemoryFlutwireStore(
  maxCalls: config.maxCalls,
  maxBytes: config.maxMemoryBytes,
);
