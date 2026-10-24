import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../l10n/strings.dart';
import '../model/body.dart';
import '../model/call.dart';
import '../util/format.dart';
import 'diff.dart';

/// One part of a comparison: the overview, the query, the header fields of a
/// request or a response, or a pair of bodies.
@immutable
final class ComparisonSection {
  /// Creates a section.
  const ComparisonSection({
    required this.title,
    required this.differences,
    this.rows = const [],
    this.message,
    this.notes = const [],
    this.lines = false,
  });

  /// What the section is about.
  final String title;

  /// How many things differ in it.
  final int differences;

  /// The rows: fields, or lines of a body when [lines] is true.
  final List<DiffRow> rows;

  /// A sentence that stands in for the rows, for bodies that are not text.
  final String? message;

  /// Things worth knowing about what the rows cover, such as a body that was
  /// cut.
  final List<String> notes;

  /// Whether [rows] are the lines of two bodies rather than named fields.
  final bool lines;

  /// Whether the two sides agree on all of it.
  bool get isIdentical => differences == 0;
}

/// Two calls set against each other, part by part.
@immutable
final class Comparison {
  /// Creates a comparison from its [sections].
  const Comparison(this.sections);

  /// Compares [left] with [right]. The parts that are empty on both sides, such
  /// as the body of two GET requests, are left out.
  factory Comparison.of(
    FlutwireCall left,
    FlutwireCall right,
    FlutwireStrings s,
  ) {
    ComparisonSection fields(String title, List<DiffRow> rows) =>
        ComparisonSection(
          title: title,
          rows: rows,
          differences: rows.where((row) => row.differs).length,
        );

    final query = diffFields(_query(left), _query(right), ignoreCase: false);
    final requestHeaders = diffFields(
      left.request.headers.entries,
      right.request.headers.entries,
    );
    final responseHeaders = diffFields(
      left.response?.headers.entries ?? const [],
      right.response?.headers.entries ?? const [],
    );
    return Comparison([
      fields(s.tabOverview, _overview(left, right, s)),
      if (query.isNotEmpty) fields(s.compareQuery, query),
      if (requestHeaders.isNotEmpty)
        fields(s.compareRequestHeaders, requestHeaders),
      ?_bodies(s.compareRequestBody, left.request.body, right.request.body, s),
      if (responseHeaders.isNotEmpty)
        fields(s.compareResponseHeaders, responseHeaders),
      ?_bodies(
        s.compareResponseBody,
        left.response?.body,
        right.response?.body,
        s,
      ),
    ]);
  }

  /// The parts, in the order they are shown.
  final List<ComparisonSection> sections;

  /// How many things differ in all of it.
  int get differences => sections.fold(0, (sum, s) => sum + s.differences);
}

List<MapEntry<String, String>> _query(FlutwireCall call) => [
  for (final entry in call.uri.queryParametersAll.entries)
    for (final value in entry.value) MapEntry(entry.key, value),
];

List<DiffRow> _overview(
  FlutwireCall left,
  FlutwireCall right,
  FlutwireStrings s,
) {
  DiffRow row(String name, String a, String b, {String? delta}) => DiffRow(
    a == b ? DiffKind.same : DiffKind.changed,
    name: name,
    left: a,
    right: a == b || delta == null ? b : '$b  ($delta)',
  );

  String path(FlutwireCall call) => call.uri.path.isEmpty ? '/' : call.uri.path;

  final leftFirst = left.timeToFirstByte;
  final rightFirst = right.timeToFirstByte;
  return [
    row(s.method, left.method, right.method),
    row(s.compareHost, left.host, right.host),
    row(s.comparePath, path(left), path(right)),
    row(s.status, _status(left, s), _status(right, s)),
    row(s.source, left.source.label, right.source.label),
    row(
      s.duration,
      formatDuration(left.duration),
      formatDuration(right.duration),
      delta: _signedDuration(right.duration - left.duration),
    ),
    if (leftFirst != null || rightFirst != null)
      row(
        s.firstByte,
        leftFirst == null ? s.compareMissing : formatDuration(leftFirst),
        rightFirst == null ? s.compareMissing : formatDuration(rightFirst),
        delta: leftFirst == null || rightFirst == null
            ? null
            : _signedDuration(rightFirst - leftFirst),
      ),
    row(
      s.requestSize,
      formatBytes(left.requestSize),
      formatBytes(right.requestSize),
      delta: _signedBytes(right.requestSize - left.requestSize),
    ),
    row(
      s.responseSize,
      formatBytes(left.responseSize),
      formatBytes(right.responseSize),
      delta: _signedBytes(right.responseSize - left.responseSize),
    ),
  ];
}

String _status(FlutwireCall call, FlutwireStrings s) {
  final response = call.response;
  if (response != null) {
    final phrase = response.reasonPhrase.isNotEmpty
        ? response.reasonPhrase
        : reasonPhraseFor(response.statusCode);
    return phrase.isEmpty
        ? '${response.statusCode}'
        : '${response.statusCode} $phrase';
  }
  return switch (call.state) {
    FlutwireCallState.pending => s.running,
    FlutwireCallState.failed => s.failed,
    FlutwireCallState.cancelled => s.cancelled,
    FlutwireCallState.completed => s.noResponseYet,
  };
}

String _signedDuration(Duration duration) =>
    '${duration.isNegative ? '-' : '+'}${formatDuration(duration.abs())}';

String _signedBytes(int bytes) =>
    '${bytes < 0 ? '-' : '+'}${formatBytes(bytes.abs())}';

/// Compares two bodies, or returns null when neither side has one.
///
/// Text is compared line by line, JSON and XML after they are laid out for
/// reading, so that a change of indentation is not a difference. A form is
/// compared field by field. Anything else, which has no lines to set against
/// each other, is compared as bytes.
ComparisonSection? _bodies(
  String title,
  FlutwireBody? left,
  FlutwireBody? right,
  FlutwireStrings s,
) {
  final a = left ?? FlutwireBody.empty();
  final b = right ?? FlutwireBody.empty();
  if (a.isEmpty && b.isEmpty) return null;
  final notes = [
    if (a.truncated)
      s.compareCut('A', formatBytes(a.bytes.length), formatBytes(a.totalBytes)),
    if (b.truncated)
      s.compareCut('B', formatBytes(b.bytes.length), formatBytes(b.totalBytes)),
  ];

  if (!_isText(a) || !_isText(b)) {
    final same = a.totalBytes == b.totalBytes && listEquals(a.bytes, b.bytes);
    return ComparisonSection(
      title: title,
      differences: same ? 0 : 1,
      notes: notes,
      message: same
          ? s.compareBinarySame(formatBytes(a.totalBytes))
          : s.compareBinaryDiffer(
              formatBytes(a.totalBytes),
              formatBytes(b.totalBytes),
            ),
    );
  }

  final isForm =
      (a.kind == FlutwireBodyKind.form || a.isEmpty) &&
      (b.kind == FlutwireBodyKind.form || b.isEmpty);
  if (isForm) {
    final rows = diffFields(a.formFields, b.formFields, ignoreCase: false);
    return ComparisonSection(
      title: title,
      rows: rows,
      differences: rows.where((row) => row.differs).length,
      notes: notes,
    );
  }

  final rows = diffLines(_linesOf(a), _linesOf(b));
  return ComparisonSection(
    title: title,
    rows: rows,
    differences: rows.where((row) => row.differs).length,
    notes: notes,
    lines: true,
  );
}

/// Whether [body] has text to compare, which an empty body does too.
bool _isText(FlutwireBody body) => body.isEmpty || body.text != null;

List<String> _linesOf(FlutwireBody body) {
  final text = body.prettyText ?? body.text ?? '';
  return text.isEmpty ? const [] : text.replaceAll('\r\n', '\n').split('\n');
}
