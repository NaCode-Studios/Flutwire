import '../model/body.dart';
import '../model/call.dart';
import '../model/headers.dart';
import '../util/format.dart';

/// One call as plain text a person can paste into a ticket or a chat.
String callToText(FlutwireCall call) {
  final response = call.response;
  final buffer = StringBuffer()
    ..writeln(_row('URL', call.uri.toString()))
    ..writeln(_row('Method', call.method))
    ..writeln(_row('Status', _status(call)))
    ..writeln(_row('Source', call.source.label))
    ..writeln(_row('Started', _timestamp(call.startedAt)))
    ..writeln(_row('Duration', _duration(call)));
  if (response?.remoteAddress != null) {
    final port = response!.remotePort;
    buffer.writeln(
      _row(
        'Remote',
        port == null
            ? response.remoteAddress!
            : '${response.remoteAddress}:$port',
      ),
    );
  }
  if (response?.certificate case final cert?) {
    buffer.writeln(_row('TLS', '${cert.subject} (issuer ${cert.issuer})'));
  }
  if (call.graphql case final graphql?) {
    buffer.writeln(_row('GraphQL', graphql.label));
  }
  buffer
    ..writeln(_row('Request size', formatBytes(call.requestSize)))
    ..writeln(_row('Response size', formatBytes(call.responseSize)));
  if (response != null && response.redirects.isNotEmpty) {
    buffer.writeln(
      _row(
        'Redirects',
        response.redirects
            .map((r) => '${r.statusCode} to ${r.location}')
            .join(', '),
      ),
    );
  }
  if (call.error case final error?) {
    buffer.writeln(_row('Error', '${error.type}: ${error.message}'));
  }

  buffer
    ..writeln()
    ..writeln('--- Request headers ---')
    ..writeln(_headers(call.request.headers))
    ..writeln()
    ..writeln('--- Request body ---')
    ..writeln(_body(call.request.body));

  if (response != null) {
    buffer
      ..writeln()
      ..writeln('--- Response headers ---')
      ..writeln(_headers(response.headers))
      ..writeln()
      ..writeln('--- Response body ---')
      ..writeln(_body(response.body));
  }
  return buffer.toString().trimRight();
}

/// Several calls as one document, oldest first, each set apart by a rule.
String callsToText(Iterable<FlutwireCall> calls, {DateTime? now}) {
  final list = calls.toList()..sort((a, b) => a.id.compareTo(b.id));
  final out = StringBuffer()
    ..writeln(
      'Flutwire export: ${list.length} '
      '${list.length == 1 ? 'call' : 'calls'}, ${_timestamp(now ?? DateTime.now())}',
    );
  for (final call in list) {
    out
      ..writeln()
      ..writeln('==================')
      ..writeln()
      ..writeln(callToText(call));
  }
  return out.toString();
}

String _row(String label, String value) => '${'$label:'.padRight(14)}$value';

String _status(FlutwireCall call) {
  final response = call.response;
  switch (call.state) {
    case FlutwireCallState.pending:
      return response == null
          ? 'pending'
          : '${response.statusCode} (receiving)';
    case FlutwireCallState.failed:
      return response == null ? 'failed' : '${response.statusCode} (failed)';
    case FlutwireCallState.cancelled:
      return response == null
          ? 'cancelled'
          : '${response.statusCode} (cancelled)';
    case FlutwireCallState.completed:
      if (response == null) return 'completed';
      final phrase = response.reasonPhrase.isNotEmpty
          ? response.reasonPhrase
          : reasonPhraseFor(response.statusCode);
      return phrase.isEmpty
          ? '${response.statusCode}'
          : '${response.statusCode} $phrase';
  }
}

String _duration(FlutwireCall call) {
  if (call.isPending) return 'still running';
  final total = formatDuration(call.duration);
  final first = call.timeToFirstByte;
  return first == null
      ? total
      : '$total (first byte after ${formatDuration(first)})';
}

String _timestamp(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = time.toLocal();
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

String _headers(FlutwireHeaders headers) => headers.isEmpty
    ? '(none)'
    : headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

String _body(FlutwireBody body) {
  if (body.isEmpty) return '(empty)';
  if (!body.loaded) return '(not loaded)';
  final text = body.prettyText;
  if (text == null) {
    return '(${body.kind == FlutwireBodyKind.image ? 'image' : 'binary data'}, '
        '${formatBytes(body.totalBytes)}${body.mimeType == null ? '' : ', ${body.mimeType}'})';
  }
  if (!body.truncated) return text;
  return '$text\n\n--- Content truncated: kept ${formatBytes(body.bytes.length)} '
      'of ${formatBytes(body.totalBytes)} ---';
}
