/// Network inspector for Flutter.
///
/// Flutwire records the HTTP calls an app makes, keeps them across restarts,
/// and opens them from a notification in the shade.
library;

export 'src/capture/recorder.dart' show FlutwireCallRecorder;
export 'src/capture/redaction.dart';
export 'src/config.dart';
export 'src/coverage.dart' show FlutwireCoverageNote, FlutwireGap;
export 'src/engine.dart' show FlutwireStandDown;
export 'src/export/export.dart' show FlutwireExportFormat, callToJson;
export 'src/flutwire.dart' show Flutwire;
export 'src/model/body.dart';
export 'src/model/call.dart';
export 'src/model/headers.dart';
export 'src/model/multipart.dart';
export 'src/store/preferences.dart';
export 'src/store/store.dart';
