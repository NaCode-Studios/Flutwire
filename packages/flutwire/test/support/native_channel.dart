import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel the native half of Flutwire answers on.
const nativeChannel = MethodChannel('it.nacodestudios.flutwire/native');

/// Makes the native half answer with [handler], or with nothing at all, which
/// is how a platform without it behaves once the channel is mocked.
///
/// The mock is removed again when the test ends.
void mockNative([Future<Object?> Function(MethodCall call)? handler]) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    nativeChannel,
    handler ?? (_) async => null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));
}

/// Plays the part of the native half telling Dart that the user tapped the
/// notification: [action] is `open` or `clear`.
Future<void> sendNativeAction(String action) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        nativeChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onAction', action),
        ),
        (_) {},
      );
}
