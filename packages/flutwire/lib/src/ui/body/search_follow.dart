import 'highlight.dart';
import 'search.dart';

/// Notices when a search arrives at a match its view has not shown yet.
///
/// A view reacts to the search controller every time it notifies, and most of
/// those notifications are about something else: the count, the input, a new
/// debounce. The tracker tells apart the one that matters, a different current
/// match, so the view scrolls to it once and never fights the user's own
/// scrolling afterwards.
final class CurrentMatchTracker {
  List<BodyMatch>? _results;
  int _index = -2;

  /// Whether the search has produced a new list of results since the last call.
  /// The match that was current then is forgotten, so [arrived] reports the
  /// first one of the new results.
  bool sawNewResults(BodySearchController search) {
    if (identical(_results, search.matches)) return false;
    _results = search.matches;
    _index = -2;
    return true;
  }

  /// The match that became current since the last call, or null if the current
  /// match is the one already shown or there is none.
  BodyMatch? arrived(BodySearchController search) {
    if (search.current < 0) {
      _index = -1;
      return null;
    }
    if (_index == search.current) return null;
    _index = search.current;
    return search.matches[search.current];
  }

  /// [sawNewResults] and [arrived] in one step, for a view that does not need
  /// to tell new results from a new current match.
  BodyMatch? advance(BodySearchController search) {
    sawNewResults(search);
    return arrived(search);
  }
}

/// The matches of a search grouped by the part of the view they belong to, so
/// that a row can ask for its own marks without looking at every match.
///
/// What a group is depends on the view. The tree and the fields view group by
/// node or field, and the parts view by part.
final class MatchGroups {
  /// Groups matches by what [groupOf] makes of each one.
  MatchGroups(this.groupOf);

  /// The group a match belongs to.
  final int Function(BodyMatch match) groupOf;

  Map<int, List<int>> _groups = const {};
  List<BodyMatch>? _grouped;

  /// Groups [matches] again, if they are not the ones grouped last time.
  void sync(List<BodyMatch> matches) {
    if (identical(matches, _grouped)) return;
    _grouped = matches;
    final groups = <int, List<int>>{};
    for (var i = 0; i < matches.length; i++) {
      (groups[groupOf(matches[i])] ??= <int>[]).add(i);
    }
    _groups = groups;
  }

  /// The marks in [group], for the matches [where] accepts when it is given,
  /// moved [shift] characters along. [sync] must have been called with the
  /// matches of [search].
  List<MatchMark> marks(
    BodySearchController search,
    int group, {
    bool Function(BodyMatch match)? where,
    int shift = 0,
  }) {
    final indices = _groups[group];
    if (indices == null) return const [];
    final matches = search.matches;
    final length = search.matchLength;
    return [
      for (final i in indices)
        if (where == null || where(matches[i]))
          (
            start: matches[i].start + shift,
            end: matches[i].start + shift + length,
            current: i == search.current,
          ),
    ];
  }
}
