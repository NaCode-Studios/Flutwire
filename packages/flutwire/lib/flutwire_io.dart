/// The `dart:io` capture, for apps that need to compose it with overrides of
/// their own. Most apps never import this: `Flutwire.init` installs it.
library;

export 'src/capture/wire/wire_io.dart'
    show FlutwireHttpClient, FlutwireHttpOverrides, installWireCapture;
