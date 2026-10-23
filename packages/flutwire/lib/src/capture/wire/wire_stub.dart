import '../../engine.dart';

/// There is no `dart:io` on this platform, so there is nothing to install.
/// Client adapters such as the Dio interceptor record calls here instead.
void Function() installWireCapture(FlutwireEngine engine) => () {};
