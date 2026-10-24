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
      breakpoints = FlutwireBreakpoints() {
    rules.addListener(_letGoOfWhatNoBreakpointHolds);
  }

  /// The rules.
  final FlutwireRules rules;

  /// The requests held at breakpoints.
  final FlutwireBreakpoints breakpoints;

  /// A breakpoint that was switched off or deleted holds nothing any more, and
  /// what it held goes on as it was. Without this the only way to free an app
  /// that a wide breakpoint holds up would be to send its requests on one by
  /// one.
  void _letGoOfWhatNoBreakpointHolds() {
    for (final held in breakpoints.held) {
      final id = held.ruleId;
      if (id != null && rules.find(id)?.enabled != true) {
        breakpoints.resume(held.id, held);
      }
    }
  }

  /// Stops what is held, so that no call stays waiting, and lets go of the
  /// listeners.
  void dispose() {
    rules.removeListener(_letGoOfWhatNoBreakpointHolds);
    breakpoints.dispose();
    rules.dispose();
  }
}
