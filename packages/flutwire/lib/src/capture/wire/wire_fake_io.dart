import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../intercept/rule.dart';
import '../../model/call.dart';
import '../../model/headers.dart';
import '../../util/format.dart';
import '../recorder.dart';

/// The header fields of a request or a response that never touched the network.
///
/// It behaves as `dart:io`'s do: names are not case sensitive and are kept in
/// lower case, a field can have several values, and the typed fields such as
/// [contentType] are read from the text and written back to it.
final class FakeHttpHeaders implements HttpHeaders {
  /// Creates the fields from [fields].
  FakeHttpHeaders([Iterable<MapEntry<String, String>> fields = const []]) {
    for (final field in fields) {
      add(field.key, field.value);
    }
  }

  final Map<String, List<String>> _values = {};
  bool _persistent = true;
  bool _chunked = false;

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) {
    final values = this[name];
    if (values == null) return null;
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.single;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    (_values[name.toLowerCase()] ??= []).add(_text(value));
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [_text(value)];
  }

  @override
  void remove(String name, Object value) {
    final key = name.toLowerCase();
    final values = _values[key];
    if (values == null) return;
    values.remove(_text(value));
    if (values.isEmpty) _values.remove(key);
  }

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void noFolding(String name) {}

  @override
  void clear() => _values.clear();

  /// Every field as a name and a value, in the order they were added.
  Iterable<MapEntry<String, String>> get entries sync* {
    for (final field in _values.entries) {
      for (final value in field.value) {
        yield MapEntry(field.key, value);
      }
    }
  }

  @override
  DateTime? get date => _date(HttpHeaders.dateHeader);

  @override
  set date(DateTime? value) => _setDate(HttpHeaders.dateHeader, value);

  @override
  DateTime? get expires => _date(HttpHeaders.expiresHeader);

  @override
  set expires(DateTime? value) => _setDate(HttpHeaders.expiresHeader, value);

  @override
  DateTime? get ifModifiedSince => _date(HttpHeaders.ifModifiedSinceHeader);

  @override
  set ifModifiedSince(DateTime? value) =>
      _setDate(HttpHeaders.ifModifiedSinceHeader, value);

  @override
  String? get host => _hostAndPort()?.$1;

  @override
  set host(String? value) => _setHost(value, port);

  @override
  int? get port => _hostAndPort()?.$2;

  @override
  set port(int? value) => _setHost(host, value);

  @override
  ContentType? get contentType {
    final text = this[HttpHeaders.contentTypeHeader]?.first;
    if (text == null) return null;
    try {
      return ContentType.parse(text);
    } on Object {
      return null;
    }
  }

  @override
  set contentType(ContentType? value) {
    if (value == null) {
      removeAll(HttpHeaders.contentTypeHeader);
    } else {
      set(HttpHeaders.contentTypeHeader, value.toString());
    }
  }

  @override
  int get contentLength =>
      int.tryParse(this[HttpHeaders.contentLengthHeader]?.first ?? '') ?? -1;

  @override
  set contentLength(int value) {
    if (value < 0) {
      removeAll(HttpHeaders.contentLengthHeader);
    } else {
      set(HttpHeaders.contentLengthHeader, value);
    }
  }

  @override
  bool get persistentConnection => _persistent;

  @override
  set persistentConnection(bool value) => _persistent = value;

  @override
  bool get chunkedTransferEncoding => _chunked;

  @override
  set chunkedTransferEncoding(bool value) => _chunked = value;

  DateTime? _date(String name) {
    final text = this[name]?.first;
    if (text == null) return null;
    try {
      return HttpDate.parse(text);
    } on Object {
      return null;
    }
  }

  void _setDate(String name, DateTime? value) {
    if (value == null) {
      removeAll(name);
    } else {
      set(name, HttpDate.format(value.toUtc()));
    }
  }

  (String, int?)? _hostAndPort() {
    final text = this[HttpHeaders.hostHeader]?.first;
    if (text == null) return null;
    final colon = text.lastIndexOf(':');
    if (colon < 0 || text.endsWith(']')) return (text, null);
    return (text.substring(0, colon), int.tryParse(text.substring(colon + 1)));
  }

  void _setHost(String? host, int? port) {
    if (host == null) {
      removeAll(HttpHeaders.hostHeader);
    } else {
      set(HttpHeaders.hostHeader, port == null ? host : '$host:$port');
    }
  }

  static String _text(Object value) =>
      value is DateTime ? HttpDate.format(value.toUtc()) : '$value';
}

/// A request that a mock rule answers, so that nothing is sent.
///
/// The app builds it as it builds any request, and what it writes is recorded;
/// when the app closes it, it gets the stored response instead of an answer
/// from the network. It never opens a connection, so it answers just as well
/// when the host cannot be reached.
final class MockHttpClientRequest implements HttpClientRequest {
  /// Creates a request for [method] to [uri] that [rule] answers.
  ///
  /// The fields that `dart:io` would add by itself are added here, so that the
  /// recorded request looks like the one that did not go out.
  MockHttpClientRequest({
    required this.method,
    required this.uri,
    required this.rule,
    required FlutwireCallRecorder? recorder,
    String? userAgent,
    bool acceptsGzip = true,
  }) : _recorder = recorder {
    final port = uri.hasPort && uri.port != 0 ? ':${uri.port}' : '';
    _headers.set(HttpHeaders.hostHeader, '${uri.host}$port');
    if (userAgent != null) _headers.set(HttpHeaders.userAgentHeader, userAgent);
    if (acceptsGzip) _headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
    _recorder?.intercepted(FlutwireIntercept.mocked);
    // The answer may never be asked for, and then nobody listens to this.
    _done.future.ignore();
  }

  /// The rule that answers.
  final FlutwireRule rule;

  final FlutwireCallRecorder? _recorder;
  final FakeHttpHeaders _headers = FakeHttpHeaders();
  final BytesBuilder _body = BytesBuilder();
  final Completer<HttpClientResponse> _done = Completer();
  final List<Cookie> _cookies = [];
  Future<HttpClientResponse>? _closing;
  Object? _failure;
  StackTrace? _failureStack;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  Encoding encoding = utf8;

  @override
  bool bufferOutput = true;

  @override
  int get contentLength => _headers.contentLength;

  @override
  set contentLength(int value) => _headers.contentLength = value;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<Cookie> get cookies => _cookies;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    if (_closing != null) return;
    _failure = exception ?? const HttpException('The request was aborted');
    _failureStack = stackTrace;
    _recorder?.cancel();
    _done.completeError(_failure!, _failureStack);
  }

  @override
  void add(List<int> data) {
    if (_closing != null) return;
    _body.add(data);
    _recorder?.requestBody(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _failure ??= error;
    _failureStack ??= stackTrace;
  }

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<HttpClientResponse> close() => _closing ??= _answer();

  @override
  Future<dynamic> flush() => Future.value();

  @override
  void write(Object? object) {
    final text = '$object';
    if (text.isNotEmpty) add(encoding.encode(text));
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final object in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      first = false;
      write(object);
    }
  }

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  Future<HttpClientResponse> _answer() async {
    final recorder = _recorder;
    final failure = _failure;
    if (failure != null) {
      recorder?.fail(failure, _failureStack);
      if (!_done.isCompleted) _done.completeError(failure, _failureStack);
      Error.throwWithStackTrace(failure, _failureStack ?? StackTrace.current);
    }
    recorder?.requestHeaders(_sentHeaders());
    recorder?.requestSent();
    final stored = rule.response!;
    if (stored.delay > Duration.zero) await Future<void>.delayed(stored.delay);
    final response = MockHttpClientResponse(stored);
    recorder
      ?..responseHead(
        statusCode: response.statusCode,
        reasonPhrase: response.reasonPhrase,
        headers: FlutwireHeaders(response._headers.entries),
      )
      ..responseBody(stored.body)
      ..complete();
    _done.complete(response);
    return response;
  }

  /// What the request would have sent: the fields the app set, the cookies it
  /// added, and the length of what it wrote.
  FlutwireHeaders _sentHeaders() {
    final fields = [..._headers.entries];
    if (_cookies.isNotEmpty) {
      fields.add(
        MapEntry(
          HttpHeaders.cookieHeader,
          _cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
        ),
      );
    }
    if (_body.length > 0 && _headers.contentLength < 0) {
      fields.add(MapEntry(HttpHeaders.contentLengthHeader, '${_body.length}'));
    }
    return FlutwireHeaders(fields);
  }
}

/// The answer of a mock rule, as `dart:io` hands one to the app.
final class MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  /// Creates the response that serves [stored].
  MockHttpClientResponse(this._stored) {
    for (final field in _stored.headers.entries) {
      if (servedHeadersLeftOut.contains(field.key.toLowerCase())) continue;
      _headers.add(field.key, field.value);
    }
    _headers.contentLength = _stored.body.length;
  }

  final FlutwireMockResponse _stored;
  final FakeHttpHeaders _headers = FakeHttpHeaders();

  @override
  int get statusCode => _stored.statusCode;

  @override
  String get reasonPhrase => _stored.reasonPhrase.isNotEmpty
      ? _stored.reasonPhrase
      : reasonPhraseFor(_stored.statusCode);

  @override
  int get contentLength => _stored.body.length;

  @override
  HttpHeaders get headers => _headers;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => true;

  @override
  bool get isRedirect =>
      const {301, 302, 303, 307, 308}.contains(statusCode) &&
      _headers[HttpHeaders.locationHeader] != null;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<Cookie> get cookies => [
    for (final line
        in _headers[HttpHeaders.setCookieHeader] ?? const <String>[])
      ?_cookie(line),
  ];

  @override
  Future<Socket> detachSocket() => Future.error(
    UnsupportedError('A response from a mock rule has no socket to detach.'),
  );

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => Future.error(
    UnsupportedError('A response from a mock rule cannot be redirected.'),
  );

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable(
        _stored.body.isEmpty ? const [] : [Uint8List.fromList(_stored.body)],
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  static Cookie? _cookie(String line) {
    try {
      return Cookie.fromSetCookieValue(line);
    } on Object {
      return null;
    }
  }
}
