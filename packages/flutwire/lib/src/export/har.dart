import 'dart:convert';

import '../model/body.dart';
import '../model/call.dart';
import '../model/cookies.dart';
import '../model/headers.dart';
import '../model/message.dart';
import '../util/format.dart';

/// The calls as a HAR 1.2 document, the format browsers and proxies import.
///
/// Compared with what a browser writes, three things differ because `dart:io`
/// does not report them: the HTTP version is always `HTTP/1.1`, and DNS,
/// connect and TLS timings are `-1` (unknown). A call that failed has status 0
/// and its error in the `_error` field, the way Chrome writes it.
Map<String, Object?> toHar(
  Iterable<FlutwireCall> calls, {
  String version = '0',
}) {
  return {
    'log': {
      'version': '1.2',
      'creator': {'name': 'Flutwire', 'version': version},
      'entries': [for (final call in calls) _entry(call)],
    },
  };
}

Map<String, Object?> _entry(FlutwireCall call) {
  final total = call.duration.inMicroseconds / 1000;
  final firstByte = call.timeToFirstByte?.inMicroseconds;
  final wait = firstByte == null ? total : firstByte / 1000;
  final receive = firstByte == null ? 0 : total - firstByte / 1000;
  final response = call.response;
  return {
    'startedDateTime': call.startedAt.toUtc().toIso8601String(),
    'time': total,
    'request': _request(call),
    'response': response == null
        ? _noResponse(call)
        : _response(call, response),
    'cache': <String, Object?>{},
    'timings': {
      'blocked': -1,
      'dns': -1,
      'connect': -1,
      'ssl': -1,
      'send': 0,
      'wait': wait,
      'receive': receive,
    },
    if (response?.remoteAddress != null)
      'serverIPAddress': response!.remoteAddress,
    if (response?.remotePort != null) 'connection': '${response!.remotePort}',
    if (call.error != null)
      '_error': '${call.error!.type}: ${call.error!.message}',
    '_flutwire': {
      'id': call.id,
      'source': call.source.label,
      'state': call.state.name,
      if (call.graphql != null) 'graphql': call.graphql!.toJson(),
    },
    ..._conversation(call),
  };
}

/// The messages of a WebSocket or an event stream, written the way Chrome
/// writes them: a WebSocket under `_webSocketMessages` with the opcode of each
/// frame, and the events of a stream under `_eventSourceMessages`.
Map<String, Object?> _conversation(FlutwireCall call) {
  final messages = call.messages;
  if (messages == null || !messages.loaded) return const {};
  double seconds(DateTime at) => at.microsecondsSinceEpoch / 1000000;
  if (messages.kind == FlutwireConversationKind.eventStream) {
    return {
      '_eventSourceMessages': [
        for (final m in messages.items)
          {
            'time': seconds(m.at),
            'eventName': m.event ?? 'message',
            'eventId': ?m.eventId,
            'data': m.text ?? '',
          },
      ],
    };
  }
  return {
    '_resourceType': 'websocket',
    '_webSocketMessages': [
      for (final m in messages.items)
        {
          'type': m.sent ? 'send' : 'receive',
          'time': seconds(m.at),
          'opcode': switch (m.kind) {
            FlutwireMessageKind.text || FlutwireMessageKind.event => 1,
            FlutwireMessageKind.binary => 2,
            FlutwireMessageKind.close => 8,
            FlutwireMessageKind.ping => 9,
            FlutwireMessageKind.pong => 10,
          },
          'data': m.kind == FlutwireMessageKind.text
              ? m.text
              : base64Encode(m.bytes),
        },
    ],
  };
}

Map<String, Object?> _request(FlutwireCall call) {
  final request = call.request;
  final body = request.body;
  return {
    'method': call.wireMethod,
    'url': call.uri.toString(),
    'httpVersion': 'HTTP/1.1',
    'cookies': _requestCookies(request.headers),
    'headers': _headers(request.headers),
    'queryString': [
      for (final p in parseFormEncoded(call.uri.query))
        {'name': p.key, 'value': p.value},
    ],
    'headersSize': -1,
    'bodySize': body.totalBytes,
    if (!body.isEmpty && body.loaded)
      'postData': {
        'mimeType': body.contentType ?? 'application/octet-stream',
        'text': body.text ?? base64Encode(body.bytes),
        if (body.text == null) 'encoding': 'base64',
        if (body.kind == FlutwireBodyKind.form)
          'params': [
            for (final f in body.formFields) {'name': f.key, 'value': f.value},
          ],
        if (body.truncated)
          'comment':
              'Body truncated: kept ${formatBytes(body.bytes.length)} of '
              '${formatBytes(body.totalBytes)}.',
      },
  };
}

Map<String, Object?> _response(FlutwireCall call, FlutwireResponse response) {
  final body = response.body;
  final isText = body.text != null;
  return {
    'status': response.statusCode,
    'statusText': response.reasonPhrase.isNotEmpty
        ? response.reasonPhrase
        : reasonPhraseFor(response.statusCode),
    'httpVersion': 'HTTP/1.1',
    'cookies': _responseCookies(response.headers),
    'headers': _headers(response.headers),
    'content': {
      'size': body.totalBytes,
      'mimeType': body.contentType ?? '',
      if (body.loaded && !body.isEmpty)
        'text': isText ? body.text : base64Encode(body.bytes),
      if (body.loaded && !body.isEmpty && !isText) 'encoding': 'base64',
      if (body.truncated)
        'comment':
            'Body truncated: kept ${formatBytes(body.bytes.length)} of '
            '${formatBytes(body.totalBytes)}.',
    },
    'redirectURL': response.headers.first('location') ?? '',
    'headersSize': -1,
    'bodySize': response.headers.contentLength ?? -1,
  };
}

Map<String, Object?> _noResponse(FlutwireCall call) => {
  'status': 0,
  'statusText': '',
  'httpVersion': 'HTTP/1.1',
  'cookies': <Object?>[],
  'headers': <Object?>[],
  'content': {'size': 0, 'mimeType': ''},
  'redirectURL': '',
  'headersSize': -1,
  'bodySize': -1,
};

List<Map<String, String>> _headers(FlutwireHeaders headers) => [
  for (final e in headers.entries) {'name': e.key, 'value': e.value},
];

List<Map<String, String>> _requestCookies(FlutwireHeaders headers) => [
  for (final line in headers['cookie'])
    for (final cookie in parseCookieHeader(line))
      {'name': cookie.name, 'value': cookie.value},
];

List<Map<String, Object?>> _responseCookies(FlutwireHeaders headers) => [
  for (final line in headers['set-cookie'])
    if (parseSetCookie(line) case final cookie?)
      {
        'name': cookie.name,
        'value': cookie.value,
        if (cookie.path != null) 'path': cookie.path,
        if (cookie.domain != null) 'domain': cookie.domain,
        if (cookie.expires != null) 'expires': cookie.expires,
        if (cookie.httpOnly) 'httpOnly': true,
        if (cookie.secure) 'secure': true,
      },
];
