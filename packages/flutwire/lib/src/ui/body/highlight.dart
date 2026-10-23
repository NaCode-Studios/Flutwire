import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../theme/tokens.dart';
import 'code_layout.dart';

/// The language whose syntax a code view colours.
enum CodeLanguage {
  /// No colouring.
  plain,

  /// JSON.
  json,

  /// XML, and HTML, whose tags and attributes look the same to the eye.
  xml,
}

/// What a coloured run of text is.
enum Syntax {
  /// A JSON key or an XML attribute name.
  key,

  /// A string, or an XML attribute value.
  string,

  /// A number.
  number,

  /// `true`, `false` and `null`.
  keyword,

  /// Braces, brackets, commas, colons and the angle brackets of tags.
  punctuation,

  /// An XML or HTML tag name.
  tag,

  /// An XML or HTML comment.
  comment,
}

/// The colour a [kind] of run is drawn in.
Color syntaxColor(FlutwireTokens tokens, Syntax kind) => switch (kind) {
  Syntax.key => tokens.syntaxKey,
  Syntax.string => tokens.syntaxString,
  Syntax.number => tokens.syntaxNumber,
  Syntax.keyword => tokens.syntaxKeyword,
  Syntax.punctuation => tokens.syntaxPunctuation,
  Syntax.tag => tokens.syntaxTag,
  Syntax.comment => tokens.syntaxPunctuation,
};

/// Receives the coloured runs a lexer finds. Text between runs is plain.
typedef SyntaxSink = void Function(int start, int end, Syntax kind);

/// Cuts text into coloured runs, one row at a time.
///
/// A lexer is a small state machine. The state at the start of a row is the
/// state at the end of the row before, which is how a string or a comment that
/// runs across the 2,000-character cut of a minified body stays one colour on
/// both sides of the cut.
abstract class SyntaxLexer {
  /// Creates a lexer.
  const SyntaxLexer();

  /// The lexer for [language].
  factory SyntaxLexer.of(CodeLanguage language) => switch (language) {
    CodeLanguage.plain => const PlainLexer(),
    CodeLanguage.json => const JsonLexer(),
    CodeLanguage.xml => const XmlLexer(),
  };

  /// The state at the start of the text, and at any point where [resetsAtLineStart].
  int get initialState => 0;

  /// Whether each new line starts from [initialState]. True for JSON, where a
  /// string cannot hold a line break, so that one stray quote spoils only its
  /// own line. False for XML, where a comment or a tag can span lines.
  bool get resetsAtLineStart;

  /// Lexes `text[start, end)` beginning in [state] and returns the state at
  /// [end]. Runs are reported to [emit], when given, clipped to the range.
  /// Lexing without an [emit] is how the state at a later row is found.
  ///
  /// Look-ahead may read past [end], but never past the end of [text].
  int lex(String text, int start, int end, int state, SyntaxSink? emit);
}

/// A lexer that finds nothing.
final class PlainLexer extends SyntaxLexer {
  /// Creates the lexer.
  const PlainLexer();

  @override
  bool get resetsAtLineStart => true;

  @override
  int lex(String text, int start, int end, int state, SyntaxSink? emit) =>
      state;
}

const int _quote = 0x22;
const int _apostrophe = 0x27;
const int _backslash = 0x5C;

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// A JSON lexer. It does not parse, so it colours a body that was cut off or
/// is not valid just as well.
final class JsonLexer extends SyntaxLexer {
  /// Creates the lexer.
  const JsonLexer();

  static const int _inString = 1;
  static const int _isKey = 2;
  static const int _escaped = 4;

  /// How far ahead the lexer reads to decide that a string is a key.
  static const int _keyLookahead = 512;

  @override
  bool get resetsAtLineStart => true;

  @override
  int lex(String text, int start, int end, int state, SyntaxSink? emit) {
    var i = start;
    var st = state;
    var runStart = start;
    while (i < end) {
      if (st & _inString != 0) {
        var escaped = st & _escaped != 0;
        var closed = false;
        while (i < end) {
          final c = text.codeUnitAt(i++);
          if (escaped) {
            escaped = false;
          } else if (c == _backslash) {
            escaped = true;
          } else if (c == _quote) {
            closed = true;
            break;
          }
        }
        emit?.call(runStart, i, st & _isKey != 0 ? Syntax.key : Syntax.string);
        st = closed ? 0 : (st & _isKey) | _inString | (escaped ? _escaped : 0);
        continue;
      }
      final c = text.codeUnitAt(i);
      if (c == _quote) {
        st = _inString | (_looksLikeKey(text, i) ? _isKey : 0);
        runStart = i++;
        // A quote on the last column still belongs to its string.
        if (i >= end) {
          emit?.call(
            runStart,
            end,
            st & _isKey != 0 ? Syntax.key : Syntax.string,
          );
        }
      } else if (_isSpace(c)) {
        i++;
      } else if (_isPunctuation(c)) {
        final s = i++;
        while (i < end && _isPunctuation(text.codeUnitAt(i))) {
          i++;
        }
        emit?.call(s, i, Syntax.punctuation);
      } else if (c == 0x2D || _isDigit(c)) {
        final s = i++;
        while (i < end && _isNumberChar(text.codeUnitAt(i))) {
          i++;
        }
        emit?.call(s, i, Syntax.number);
      } else if (_isAsciiLetter(c)) {
        final s = i++;
        while (i < end && _isAsciiLetter(text.codeUnitAt(i))) {
          i++;
        }
        if (_isKeyword(text, s, i)) emit?.call(s, i, Syntax.keyword);
      } else {
        i++;
      }
    }
    return st;
  }

  static bool _isPunctuation(int c) =>
      c == 0x7B ||
      c == 0x7D ||
      c == 0x5B ||
      c == 0x5D ||
      c == 0x2C ||
      c == 0x3A;

  static bool _isNumberChar(int c) =>
      _isDigit(c) ||
      c == 0x2E ||
      c == 0x65 ||
      c == 0x45 ||
      c == 0x2B ||
      c == 0x2D;

  static bool _isKeyword(String text, int start, int end) {
    final length = end - start;
    if (length == 4) {
      return text.startsWith('true', start) || text.startsWith('null', start);
    }
    return length == 5 && text.startsWith('false', start);
  }

  /// Whether the string that opens at [quoteAt] is followed by a colon, which
  /// makes it a key. The look-ahead is bounded so that a very long string
  /// costs a constant, and a string that long is not a key anyway.
  static bool _looksLikeKey(String text, int quoteAt) {
    final limit = math.min(text.length, quoteAt + 1 + _keyLookahead);
    var j = quoteAt + 1;
    var escaped = false;
    while (j < limit) {
      final c = text.codeUnitAt(j++);
      if (escaped) {
        escaped = false;
      } else if (c == _backslash) {
        escaped = true;
      } else if (c == _quote) {
        final after = math.min(text.length, j + 64);
        while (j < after) {
          final d = text.codeUnitAt(j++);
          if (!_isSpace(d)) return d == 0x3A;
        }
        return false;
      }
    }
    return false;
  }
}

/// An XML and HTML lexer. It colours tags, attribute names and values, and
/// comments, and it does not care whether the document is well formed.
final class XmlLexer extends SyntaxLexer {
  /// Creates the lexer.
  const XmlLexer();

  static const int _text = 0;
  static const int _tagName = 1;
  static const int _inTag = 2;
  static const int _doubleQuoted = 3;
  static const int _singleQuoted = 4;
  static const int _comment = 5;
  static const int _cdata = 6;

  @override
  bool get resetsAtLineStart => false;

  @override
  int lex(String text, int start, int end, int state, SyntaxSink? emit) {
    var i = start;
    var st = state;
    var runStart = start;
    while (i < end) {
      if (st == _text) {
        final lt = _find(text, 0x3C, i, end);
        if (lt < 0) {
          i = end;
          continue;
        }
        i = lt;
        if (text.startsWith('<!--', i)) {
          st = _comment;
          runStart = i;
          i = math.min(i + 4, end);
          if (i >= end) emit?.call(runStart, end, Syntax.comment);
          continue;
        }
        if (text.startsWith('<![CDATA[', i)) {
          st = _cdata;
          i = math.min(i + 9, end);
          continue;
        }
        final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : -1;
        if (next == 0x2F || next == 0x3F || next == 0x21) {
          final stop = math.min(i + 2, end);
          emit?.call(i, stop, Syntax.punctuation);
          i = stop;
          st = _tagName;
        } else if (next >= 0 && _isNameStart(next)) {
          emit?.call(i, i + 1, Syntax.punctuation);
          i++;
          st = _tagName;
        } else {
          i++; // a lone angle bracket is text
        }
      } else if (st == _tagName) {
        final s = i;
        while (i < end && _isNameChar(text.codeUnitAt(i))) {
          i++;
        }
        if (i > s) emit?.call(s, i, Syntax.tag);
        // A name that runs to the end of the row may go on in the next one.
        if (i < end) st = _inTag;
      } else if (st == _inTag) {
        final c = text.codeUnitAt(i);
        if (_isSpace(c)) {
          i++;
        } else if (c == 0x3E) {
          emit?.call(i, i + 1, Syntax.punctuation);
          i++;
          st = _text;
        } else if ((c == 0x2F || c == 0x3F) &&
            i + 1 < text.length &&
            text.codeUnitAt(i + 1) == 0x3E) {
          final stop = math.min(i + 2, end);
          emit?.call(i, stop, Syntax.punctuation);
          i = stop;
          st = _text;
        } else if (c == _quote || c == _apostrophe) {
          st = c == _quote ? _doubleQuoted : _singleQuoted;
          runStart = i++;
          if (i >= end) emit?.call(runStart, end, Syntax.string);
        } else if (c == 0x3D) {
          emit?.call(i, i + 1, Syntax.punctuation);
          i++;
        } else if (_isNameStart(c)) {
          final s = i++;
          while (i < end && _isNameChar(text.codeUnitAt(i))) {
            i++;
          }
          emit?.call(s, i, Syntax.key);
        } else {
          i++;
        }
      } else if (st == _doubleQuoted || st == _singleQuoted) {
        final q = _find(
          text,
          st == _doubleQuoted ? _quote : _apostrophe,
          i,
          end,
        );
        if (q < 0) {
          emit?.call(runStart, end, Syntax.string);
          i = end;
        } else {
          emit?.call(runStart, q + 1, Syntax.string);
          i = q + 1;
          st = _inTag;
        }
      } else if (st == _comment) {
        final at = _findSequence(text, '-->', i, end);
        if (at < 0) {
          emit?.call(runStart, end, Syntax.comment);
          i = end;
        } else {
          final stop = math.min(at + 3, end);
          emit?.call(runStart, stop, Syntax.comment);
          i = stop;
          st = _text;
        }
      } else {
        final at = _findSequence(text, ']]>', i, end);
        if (at < 0) {
          i = end;
        } else {
          i = math.min(at + 3, end);
          st = _text;
        }
      }
    }
    return st;
  }

  static bool _isNameStart(int c) =>
      _isAsciiLetter(c) || c == 0x5F || c == 0x3A || c > 0x7F;

  static bool _isNameChar(int c) =>
      _isNameStart(c) || _isDigit(c) || c == 0x2D || c == 0x2E;

  static int _find(String text, int unit, int from, int end) {
    for (var i = from; i < end; i++) {
      if (text.codeUnitAt(i) == unit) return i;
    }
    return -1;
  }

  /// The index of [sequence] if it begins inside `[from, end)`, or -1.
  static int _findSequence(String text, String sequence, int from, int end) {
    final first = sequence.codeUnitAt(0);
    for (var i = from; i < end; i++) {
      if (text.codeUnitAt(i) == first && text.startsWith(sequence, i)) {
        return i;
      }
    }
    return -1;
  }
}

/// Finds the coloured runs of the rows of a [CodeLayout], as they are asked
/// for.
///
/// Nothing is lexed up front. The state at the start of a row is found by
/// lexing the rows before it that belong to the same line, once, and the runs
/// of a row are kept in a small cache so that scrolling back and forth over the
/// same rows costs nothing.
final class CodeHighlighter {
  /// Creates a highlighter for the rows of [layout].
  CodeHighlighter(this.layout, this.lexer, {this.cacheRows = 256})
    : _states = Uint8List(layout.rowCount);

  /// The rows that are coloured.
  final CodeLayout layout;

  /// The lexer that colours them.
  final SyntaxLexer lexer;

  /// How many rows of runs are kept.
  final int cacheRows;

  final Uint8List _states;
  int _known = 0;
  final LinkedHashMap<int, List<int>> _cache = LinkedHashMap();

  /// The runs of [row] as a flat list of `start, end, kind index` triples, in
  /// order, with offsets into the text.
  List<int> runsFor(int row) {
    final cached = _cache.remove(row);
    if (cached != null) {
      _cache[row] = cached;
      return cached;
    }
    final out = <int>[];
    lexer.lex(layout.text, layout.start(row), layout.end(row), _stateAt(row), (
      start,
      end,
      kind,
    ) {
      out
        ..add(start)
        ..add(end)
        ..add(kind.index);
    });
    _cache[row] = out;
    if (_cache.length > cacheRows) _cache.remove(_cache.keys.first);
    return out;
  }

  int _stateAt(int row) {
    while (_known <= row) {
      final k = _known;
      if (k == 0 || (lexer.resetsAtLineStart && layout.isFirstOfLine(k))) {
        _states[k] = lexer.initialState;
      } else {
        _states[k] = lexer.lex(
          layout.text,
          layout.start(k - 1),
          layout.end(k - 1),
          _states[k - 1],
          null,
        );
      }
      _known++;
    }
    return _states[row];
  }
}

/// A span of text a search match covers.
typedef MatchMark = ({int start, int end, bool current});

/// Builds the spans for `text[start, end)`, cut where a coloured run or a
/// search match begins or ends.
///
/// [runs] is the flat triple list [CodeHighlighter.runsFor] returns, and
/// [marks] the matches, both in order and without overlaps. A match is drawn
/// on a background, and the current one on the stronger background with ink
/// that stays readable on it.
List<InlineSpan> styledSpans({
  required String text,
  required int start,
  required int end,
  required FlutwireTokens tokens,
  List<int> runs = const [],
  List<MatchMark> marks = const [],
}) {
  final spans = <InlineSpan>[];
  var pos = start;
  var r = 0;
  var m = 0;
  while (pos < end) {
    while (r < runs.length && runs[r + 1] <= pos) {
      r += 3;
    }
    while (m < marks.length && marks[m].end <= pos) {
      m++;
    }
    Color? color;
    var limit = end;
    if (r < runs.length) {
      if (runs[r] <= pos) {
        color = syntaxColor(tokens, Syntax.values[runs[r + 2]]);
        limit = math.min(limit, runs[r + 1]);
      } else {
        limit = math.min(limit, runs[r]);
      }
    }
    Color? background;
    if (m < marks.length) {
      final mark = marks[m];
      if (mark.start <= pos) {
        background = mark.current ? tokens.currentMatch : tokens.match;
        if (mark.current) color = tokens.isDark ? tokens.ground : tokens.ink;
        limit = math.min(limit, mark.end);
      } else {
        limit = math.min(limit, mark.start);
      }
    }
    spans.add(
      TextSpan(
        text: text.substring(pos, limit),
        style: color == null && background == null
            ? null
            : TextStyle(color: color, backgroundColor: background),
      ),
    );
    pos = limit;
  }
  return spans;
}
