import 'package:flutter/foundation.dart';

/// A way in which Flutwire may be missing calls.
enum FlutwireGap {
  /// A client adapter stood down because the `dart:io` capture records its
  /// calls, and the capture never saw one. The client probably does not use
  /// `dart:io`, as is the case for `cronet_http`, `cupertino_http` and a Dio
  /// adapter with a transport of its own.
  clientBypassesDartIo,

  /// Something replaced `HttpOverrides` without chaining to the one Flutwire
  /// installed, so the `dart:io` capture no longer sees anything.
  captureReplaced,

  /// A Flutwire adapter ran in an isolate that did not attach to Flutwire.
  /// Overrides belong to one isolate, so what that isolate sends is not
  /// recorded.
  otherIsolate,
}

/// One reason Flutwire may be missing calls, with how often it was seen.
@immutable
final class FlutwireCoverageNote {
  /// Creates a note.
  const FlutwireCoverageNote({
    required this.gap,
    required this.subject,
    required this.lastSeen,
    this.count = 1,
  });

  /// What kind of blind spot this is.
  final FlutwireGap gap;

  /// What it is about: a client and a host, or an isolate. Notes with the same
  /// [gap] and [subject] are one note.
  final String subject;

  /// How many times it was seen.
  final int count;

  /// When it was last seen.
  final DateTime lastSeen;

  FlutwireCoverageNote _seenAgain(DateTime now) => FlutwireCoverageNote(
    gap: gap,
    subject: subject,
    lastSeen: now,
    count: count + 1,
  );
}

/// What Flutwire has noticed about its own blind spots.
///
/// The notes come from observation rather than from a list of known packages:
/// an adapter that stood down for a call the capture never saw, a capture that
/// is no longer installed, an adapter running in an isolate with no recorder.
final class FlutwireCoverage {
  /// Creates an empty record that keeps at most [limit] notes.
  FlutwireCoverage({this.limit = 20});

  /// The most notes kept. A client used against many hosts would otherwise grow
  /// the list without end.
  final int limit;

  final ValueNotifier<List<FlutwireCoverageNote>> _notes = ValueNotifier(
    const [],
  );

  /// The notes, in the order they were first seen. Empty while nothing is
  /// wrong.
  ValueListenable<List<FlutwireCoverageNote>> get notes => _notes;

  /// Says that [gap] was seen again about [subject].
  void report(FlutwireGap gap, String subject, DateTime now) {
    final list = [..._notes.value];
    final index = list.indexWhere((n) => n.gap == gap && n.subject == subject);
    if (index >= 0) {
      list[index] = list[index]._seenAgain(now);
    } else if (list.length < limit) {
      list.add(FlutwireCoverageNote(gap: gap, subject: subject, lastSeen: now));
    } else {
      return;
    }
    _notes.value = List.unmodifiable(list);
  }

  /// Forgets every note about [gap], because it is no longer the case.
  void resolve(FlutwireGap gap) {
    final kept = _notes.value.where((n) => n.gap != gap).toList();
    if (kept.length != _notes.value.length) {
      _notes.value = List.unmodifiable(kept);
    }
  }

  /// Releases the listeners.
  void dispose() => _notes.dispose();
}
