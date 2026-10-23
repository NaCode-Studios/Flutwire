import 'dart:convert';

import '../model/body.dart';
import '../model/call.dart';
import 'curl.dart';
import 'har.dart';
import 'text.dart';

/// A way to write calls out of the inspector.
enum FlutwireExportFormat {
  /// Plain text, for a ticket or a chat message.
  text('txt', 'text/plain', 'Text'),

  /// A shell command that repeats the call.
  curl('sh', 'text/x-shellscript', 'cURL'),

  /// HAR 1.2, which browsers and proxies import.
  har('har', 'application/json', 'HAR'),

  /// Flutwire's own JSON, with the bodies included.
  json('json', 'application/json', 'JSON');

  const FlutwireExportFormat(this.extension, this.mimeType, this.label);

  /// The file extension, without a dot.
  final String extension;

  /// The media type of a file in this format.
  final String mimeType;

  /// The name shown in menus.
  final String label;

  /// Writes [calls] in this format. The calls must have their bodies loaded.
  String render(Iterable<FlutwireCall> calls, {String version = '0'}) {
    final list = calls.toList();
    switch (this) {
      case FlutwireExportFormat.text:
        return callsToText(list);
      case FlutwireExportFormat.curl:
        final ordered = [...list]..sort((a, b) => a.id.compareTo(b.id));
        return ordered.map(toCurl).join('\n\n');
      case FlutwireExportFormat.har:
        final ordered = [...list]..sort((a, b) => a.id.compareTo(b.id));
        return const JsonEncoder.withIndent(
          '  ',
        ).convert(toHar(ordered, version: version));
      case FlutwireExportFormat.json:
        final ordered = [...list]..sort((a, b) => a.id.compareTo(b.id));
        return const JsonEncoder.withIndent('  ').convert({
          'flutwire': 1,
          'calls': [for (final c in ordered) callToJson(c)],
        });
    }
  }
}

/// A call as JSON with its bodies included, text as text and anything else
/// as base64.
Map<String, Object?> callToJson(FlutwireCall call) {
  final json = call.toJson();
  (json['request']! as Map<String, Object?>)['body'] = _bodyToJson(
    call.request.body,
  );
  final response = call.response;
  if (response != null) {
    (json['response']! as Map<String, Object?>)['body'] = _bodyToJson(
      response.body,
    );
  }
  return json;
}

Map<String, Object?> _bodyToJson(FlutwireBody body) => {
  ...body.toJson(),
  'truncated': body.truncated,
  if (body.loaded && !body.isEmpty)
    if (body.text != null)
      'text': body.text
    else
      'base64': base64Encode(body.bytes),
};
