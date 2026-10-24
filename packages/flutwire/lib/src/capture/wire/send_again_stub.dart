import '../../engine.dart';
import '../../resend.dart';

/// There is no `dart:io` on this platform, so a request cannot be sent again.
const bool canSendAgain = false;

/// Never called where [canSendAgain] is false.
Future<int?> sendAgain(
  FlutwireEngine engine,
  FlutwireResend request, {
  Duration deadline = const Duration(minutes: 2),
}) =>
    throw UnsupportedError('A request cannot be sent again on this platform.');
