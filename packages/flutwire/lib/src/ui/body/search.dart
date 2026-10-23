import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scope.dart';

/// The fewest characters a query needs before anything is searched for.
const int bodySearchMinLength = 2;

/// The most matches the search keeps. Past it the count reads "10,000+", which
/// bounds the work and the memory a search on a very common word can cost.
const int bodySearchMatchCap = 10000;

/// How long typing must pause before a search runs.
const Duration bodySearchDebounce = Duration(milliseconds: 200);

/// The key of the text that counts the matches, for tests to find.
const Key bodySearchCounterKey = ValueKey<String>('flutwire.body.counter');

/// One hit of a search.
@immutable
final class BodyMatch {
  /// Creates a match at [start] inside the searchable [unit].
  const BodyMatch(this.unit, this.start);

  /// Which piece of text the match is in. What a unit is depends on the view:
  /// the whole text for code, a key or a value for the tree and the fields.
  final int unit;

  /// Where the match begins inside that unit, in UTF-16 code units.
  final int start;
}

/// The text a view can be searched through, cut into units.
abstract interface class BodySearchSource {
  /// Calls [visit] for every unit in document order. [visit] returns false to
  /// stop early. Unit ids must increase.
  void forEachUnit(bool Function(int unit, String text) visit);
}

/// A [BodySearchSource] with a single unit: one text.
final class TextSearchSource implements BodySearchSource {
  /// Searches through [text].
  const TextSearchSource(this.text);

  /// The text on screen.
  final String text;

  @override
  void forEachUnit(bool Function(int unit, String text) visit) {
    visit(0, text);
  }
}

/// Lower-cases [text] without ever changing its length.
///
/// Offsets found in the folded text must be valid in the original, and a few
/// characters (the Turkish dotted capital I) lower-case to two code units.
String foldCase(String text) {
  final lower = text.toLowerCase();
  if (lower.length == text.length) return lower;
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    final one = String.fromCharCode(unit);
    final folded = one.toLowerCase();
    out.write(folded.length == 1 ? folded : one);
  }
  return out.toString();
}

/// The outcome of one search.
typedef BodySearchResult = ({List<BodyMatch> matches, bool capped});

/// Finds every non-overlapping occurrence of [query] in [source].
///
/// The query is a literal, never a pattern, so `(`, `.`, `[` and `*` mean what
/// they say. Case is ignored. At most [bodySearchMatchCap] matches are kept and
/// [BodySearchResult.capped] says whether there were more.
BodySearchResult findBodyMatches(BodySearchSource source, String query) {
  final needle = foldCase(query);
  final matches = <BodyMatch>[];
  var capped = false;
  if (needle.isEmpty) return (matches: matches, capped: false);
  source.forEachUnit((unit, text) {
    if (text.length < needle.length) return true;
    final haystack = foldCase(text);
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) return true;
      if (matches.length >= bodySearchMatchCap) {
        capped = true;
        return false;
      }
      matches.add(BodyMatch(unit, at));
      from = at + needle.length;
    }
  });
  return (matches: matches, capped: capped);
}

/// The state of the search bar, shared by the bar and the view it searches.
///
/// The controller owns the work: the views only read [matches] and [current]
/// when they build, so a view never has to report a result back up while the
/// tree is being built.
final class BodySearchController extends ChangeNotifier {
  /// Creates a controller that waits [debounce] after typing stops.
  BodySearchController({this.debounce = bodySearchDebounce});

  /// How long typing must pause before a search runs.
  final Duration debounce;

  BodySearchSource? _source;
  String _input = '';
  String _query = '';
  List<BodyMatch> _matches = const [];
  bool _capped = false;
  int _current = -1;
  Timer? _timer;

  /// The text the search runs through. A view compares it with its own source
  /// to tell a change meant for it from one meant for the view it replaced.
  BodySearchSource? get source => _source;

  /// What the user has typed so far.
  String get input => _input;

  /// The query the current [matches] belong to, or empty when no search ran.
  String get query => _query;

  /// How long a match is, in code units. The same for every match.
  int get matchLength => _query.length;

  /// The matches, in document order.
  List<BodyMatch> get matches => _matches;

  /// Whether the search stopped at [bodySearchMatchCap].
  bool get capped => _capped;

  /// The index into [matches] of the match the search is on, or -1.
  int get current => _current;

  /// Whether the typed text is long enough to be searched for.
  bool get hasQuery => _input.runes.length >= bodySearchMinLength;

  /// Whether the matches are those of what is typed now, and not of an earlier
  /// text that is waiting to be replaced.
  bool get isSettled => _query == _input;

  /// Points the search at the text of the view on screen, and searches it
  /// again with the query that is typed.
  void attach(BodySearchSource? source) {
    _source = source;
    _timer?.cancel();
    if (hasQuery && source != null) {
      _run();
    } else {
      _drop();
    }
  }

  /// Records what the user typed. The search runs once typing pauses.
  void setInput(String value) {
    if (value == _input) return;
    _input = value;
    _timer?.cancel();
    if (!hasQuery || _source == null) {
      _drop();
      return;
    }
    _timer = Timer(debounce, _run);
  }

  /// Moves to the next match, wrapping from the last to the first.
  void next() {
    if (_matches.isEmpty) return;
    _current = (_current + 1) % _matches.length;
    notifyListeners();
  }

  /// Moves to the previous match, wrapping from the first to the last.
  void previous() {
    if (_matches.isEmpty) return;
    _current = (_current - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  /// Forgets the query and every match, so that no highlight remains.
  void clear() {
    _timer?.cancel();
    _input = '';
    _drop();
  }

  void _run() {
    final source = _source;
    if (source == null) return;
    final result = findBodyMatches(source, _input);
    _query = _input;
    _matches = result.matches;
    _capped = result.capped;
    _current = _matches.isEmpty ? -1 : 0;
    notifyListeners();
  }

  void _drop() {
    _query = '';
    _matches = const [];
    _capped = false;
    _current = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The search bar at the bottom of the viewer.
class BodySearchBar extends StatefulWidget {
  /// Creates the bar for [controller]. [onClose] is called to dismiss it.
  const BodySearchBar({
    super.key,
    required this.controller,
    required this.onClose,
  });

  /// The search the bar drives.
  final BodySearchController controller;

  /// Called when the user dismisses the bar.
  final VoidCallback onClose;

  @override
  State<BodySearchBar> createState() => _BodySearchBarState();
}

class _BodySearchBarState extends State<BodySearchBar> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.text = widget.controller.input;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clearText() {
    _text.clear();
    widget.controller.setInput('');
  }

  String _counter(BuildContext context) {
    final c = widget.controller;
    final strings = context.strings;
    if (!c.hasQuery || !c.isSettled) return '';
    if (c.matches.isEmpty) return strings.noMatches;
    return c.capped
        ? strings.matchCounterCapped(c.current + 1, c.matches.length)
        : strings.matchCounter(c.current + 1, c.matches.length);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final strings = context.strings;
    final controller = widget.controller;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onClose,
              },
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _text,
                builder: (context, value, _) => TextField(
                  controller: _text,
                  autofocus: true,
                  style: tokens.mono(size: 13, color: tokens.ink),
                  cursorColor: tokens.syntaxKey,
                  textInputAction: TextInputAction.search,
                  // Enter steps to the next match and keeps the keyboard up,
                  // which is what a search box is for. The default would
                  // dismiss it.
                  onEditingComplete: controller.next,
                  onChanged: controller.setInput,
                  decoration: InputDecoration(
                    hintText: strings.searchInBody,
                    hintStyle: tokens.body(color: tokens.faint),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: tokens.faint,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 40,
                    ),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clear,
                            iconSize: 18,
                            onPressed: _clearText,
                            icon: const Icon(Icons.cancel_rounded),
                          ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final counter = _counter(context);
              return ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    counter,
                    key: bodySearchCounterKey,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: tokens.mono(size: 11.5, color: tokens.muted),
                  ),
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final hasMatches = controller.matches.isNotEmpty;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BarButton(
                    tooltip: strings.previousMatch,
                    icon: Icons.keyboard_arrow_up_rounded,
                    onPressed: hasMatches ? controller.previous : null,
                  ),
                  _BarButton(
                    tooltip: strings.nextMatch,
                    icon: Icons.keyboard_arrow_down_rounded,
                    onPressed: hasMatches ? controller.next : null,
                  ),
                ],
              );
            },
          ),
          _BarButton(
            tooltip: strings.close,
            icon: Icons.close_rounded,
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      icon: Icon(icon),
    );
  }
}
