import 'dart:io';

import '../config.dart';
import '../diagnostics.dart';
import 'disk_store.dart';
import 'store.dart';

/// Opens the store the configuration asks for.
///
/// With persistence on, the history goes to `config.storagePath`, or to the
/// folder [defaultPath] resolves, or to a per-user folder derived from the
/// environment on desktop. If no folder can be found or opened, the history is
/// kept in memory instead, because losing persistence must never cost the app
/// its inspector.
Future<FlutwireStore> openStore(
  FlutwireConfig config, {
  Future<String?> Function()? defaultPath,
}) async {
  MemoryFlutwireStore memory() => MemoryFlutwireStore(
    maxCalls: config.maxCalls,
    maxBytes: config.maxMemoryBytes,
  );
  if (!config.persist) return memory();
  try {
    final base = config.storagePath ?? await defaultPath?.call() ?? _desktop();
    if (base == null) return memory();
    final root = config.storagePath != null
        ? Directory(base)
        : Directory('$base/flutwire');
    return await DiskFlutwireStore.open(root, config);
  } on Object catch (error, stack) {
    reportProblem(
      'Could not open the history on disk, so it is kept in memory only.',
      error: error,
      stack: stack,
    );
    return memory();
  }
}

String? _desktop() {
  final env = Platform.environment;
  if (Platform.isWindows) {
    final base = env['LOCALAPPDATA'] ?? env['APPDATA'];
    return base == null ? null : '$base\\Flutwire';
  }
  if (Platform.isLinux) {
    final data = env['XDG_DATA_HOME'];
    if (data != null && data.isNotEmpty) return data;
    final home = env['HOME'];
    return home == null ? null : '$home/.local/share';
  }
  return null;
}
