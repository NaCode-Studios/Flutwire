/// Firebase Cloud Functions for Flutwire.
///
/// A callable function is called through the native Firebase SDK, which never
/// goes through `dart:io`, so the capture that records every other call cannot
/// see it. [FlutwireCloudFunctions.install] puts Flutwire between the app and
/// the plugin so these calls are recorded too.
library;

export 'src/install.dart' show FlutwireCloudFunctions;
