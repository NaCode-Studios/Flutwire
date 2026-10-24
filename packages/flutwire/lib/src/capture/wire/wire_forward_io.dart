import 'dart:convert';
import 'dart:io';

/// A request that is the one it wraps, until a subclass changes what it does
/// with what the app writes and with the end of the request.
///
/// Everything the app can read or set on a request before it is closed, such as
/// the header fields, the cookies and the redirect settings, belongs to the
/// request underneath, so that the app finds there what it put there. A
/// subclass decides what happens to [add], [addStream], [close], [done] and
/// [abort].
abstract class ForwardingHttpClientRequest implements HttpClientRequest {
  /// Wraps [inner].
  ForwardingHttpClientRequest(this.inner);

  /// The request this one wraps.
  final HttpClientRequest inner;

  @override
  bool get bufferOutput => inner.bufferOutput;
  @override
  set bufferOutput(bool value) => inner.bufferOutput = value;
  @override
  int get contentLength => inner.contentLength;
  @override
  set contentLength(int value) => inner.contentLength = value;
  @override
  Encoding get encoding => inner.encoding;
  @override
  set encoding(Encoding value) => inner.encoding = value;
  @override
  bool get followRedirects => inner.followRedirects;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;
  @override
  int get maxRedirects => inner.maxRedirects;
  @override
  set maxRedirects(int value) => inner.maxRedirects = value;
  @override
  bool get persistentConnection => inner.persistentConnection;
  @override
  set persistentConnection(bool value) => inner.persistentConnection = value;
  @override
  HttpConnectionInfo? get connectionInfo => inner.connectionInfo;
  @override
  List<Cookie> get cookies => inner.cookies;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  String get method => inner.method;
  @override
  Uri get uri => inner.uri;

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);

  @override
  Future<dynamic> flush() => inner.flush();

  @override
  void write(Object? object) {
    final text = '$object';
    if (text.isEmpty) return;
    add(encoding.encode(text));
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
}
