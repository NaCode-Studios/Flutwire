import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/body/search.dart';
import 'package:flutwire/src/ui/body/search_follow.dart';

/// A source of several units, each its own text.
final class _Units implements BodySearchSource {
  const _Units(this.texts);

  final List<String> texts;

  @override
  void forEachUnit(bool Function(int unit, String text) visit) {
    for (var i = 0; i < texts.length; i++) {
      if (!visit(i, texts[i])) return;
    }
  }
}

BodySearchController searching(BodySearchSource source, String query) {
  final controller = BodySearchController(debounce: Duration.zero)
    ..setInput(query)
    ..attach(source);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  group('CurrentMatchTracker', () {
    test('reports the first match once the results arrive', () {
      final search = searching(const TextSearchSource('ab ab ab'), 'ab');
      final tracker = CurrentMatchTracker();

      final first = tracker.advance(search);

      expect(first?.start, 0);
    });

    test('stays quiet while the current match is the one already shown', () {
      final search = searching(const TextSearchSource('ab ab ab'), 'ab');
      final tracker = CurrentMatchTracker()..advance(search);

      expect(tracker.advance(search), isNull);
      expect(tracker.advance(search), isNull);
    });

    test('reports each match the search moves to', () {
      final search = searching(const TextSearchSource('ab ab ab'), 'ab');
      final tracker = CurrentMatchTracker()..advance(search);

      search.next();
      expect(tracker.advance(search)?.start, 3);

      search.next();
      expect(tracker.advance(search)?.start, 6);

      search.next();
      expect(tracker.advance(search)?.start, 0);
    });

    test('starts over when the results are replaced', () {
      final search = searching(const TextSearchSource('ab ab'), 'ab');
      final tracker = CurrentMatchTracker()..advance(search);

      search.attach(const TextSearchSource('xx ab'));

      expect(tracker.advance(search)?.start, 3);
    });

    test('has nothing to report when nothing matches', () {
      final search = searching(const TextSearchSource('hello'), 'zz');
      final tracker = CurrentMatchTracker();

      expect(tracker.advance(search), isNull);
    });

    test('knows new results from a new current match', () {
      final search = searching(const TextSearchSource('ab ab'), 'ab');
      final tracker = CurrentMatchTracker();

      expect(tracker.sawNewResults(search), isTrue);
      expect(tracker.sawNewResults(search), isFalse);
      expect(tracker.arrived(search)?.start, 0);

      search.next();
      expect(tracker.sawNewResults(search), isFalse);
      expect(tracker.arrived(search)?.start, 3);
    });
  });

  group('MatchGroups', () {
    const source = _Units(['red green', 'green', 'blue green']);

    test('hands a group the marks of its own matches', () {
      final search = searching(source, 'green');
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);

      final marks = groups.marks(search, 2);

      expect(marks, hasLength(1));
      expect(marks.single.start, 5);
      expect(marks.single.end, 10);
    });

    test('marks the current match, and only that one', () {
      final search = searching(source, 'green')..next();
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);

      expect(groups.marks(search, 0).single.current, isFalse);
      expect(groups.marks(search, 1).single.current, isTrue);
    });

    test('has no marks for a group without a match', () {
      final search = searching(source, 'blue');
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);

      expect(groups.marks(search, 0), isEmpty);
      expect(groups.marks(search, 99), isEmpty);
    });

    test('keeps only the matches the filter accepts', () {
      final search = searching(const _Units(['aa aa']), 'aa');
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);

      final marks = groups.marks(search, 0, where: (match) => match.start > 0);

      expect(marks.map((mark) => mark.start), [3]);
    });

    test('moves the marks along when asked', () {
      final search = searching(const _Units(['green']), 'green');
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);

      final mark = groups.marks(search, 0, shift: 1).single;

      expect((mark.start, mark.end), (1, 6));
    });

    test('groups again when the results are replaced', () {
      final search = searching(source, 'green');
      final groups = MatchGroups((match) => match.unit)..sync(search.matches);
      search
        ..setInput('blue')
        ..attach(source);

      groups.sync(search.matches);

      expect(groups.marks(search, 0), isEmpty);
      expect(groups.marks(search, 2), hasLength(1));
    });
  });
}
