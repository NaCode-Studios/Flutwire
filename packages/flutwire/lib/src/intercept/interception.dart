import '../store/preferences.dart';
import 'breakpoints.dart';
import 'rules.dart';

/// What lets Flutwire change traffic: the rules that answer a request or hold
/// it, and the requests that are held.
///
/// It exists only when the app asked for it, with
/// `FlutwireConfig.interception`. Without it Flutwire only reads.
final class FlutwireInterception {
  /// Creates the rules over [preferences], which keep them from one run to the
  /// next, and an empty set of held requests.
  FlutwireInterception(FlutwirePreferences preferences)
    : rules = FlutwireRules(preferences),
      breakpoints = FlutwireBreakpoints();

  /// The rules.
  final FlutwireRules rules;

  /// The requests held at breakpoints.
  final FlutwireBreakpoints breakpoints;

  /// Stops what is held, so that no call stays waiting, and lets go of the
  /// listeners.
  void dispose() {
    breakpoints.dispose();
    rules.dispose();
  }
}
