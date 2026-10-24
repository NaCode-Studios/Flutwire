import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../engine.dart';
import '../../model/call.dart';
import '../../model/headers.dart';
import '../recorder.dart';

/// Records every call made through `dart:io`, with no setup in the client.
///
/// `package:http`, Dio's default adapter, Chopper, `Image.network` and most
/// SDKs that talk HTTP from Dart create their client with `HttpClient()`. This
/// override hands each of them a thin wrapper around the real client, which
/// observes the request and the response and changes neither.
///
/// Compose it with overrides the app already has through [previous]; calls
/// that Flutwire does not record, such as ignored ones, get the real request
/// object with nothing in between.
final class FlutwireHttpOverrides extends HttpOverrides {
  /// Creates an override that reports to [engine].
  FlutwireHttpOverrides(this.engine, {HttpOverrides? previous})
    : _previous = previous;

  /// The engine that records the calls.
  final FlutwireEngine engine;

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final previous = _previous;
    final inner = previous != null
        ? previous.createHttpClient(context)
        : super.createHttpClient(context);
    return FlutwireHttpClient(inner, engine);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    final previous = _previous;
    return previous != null
        ? previous.findProxyFromEnvironment(url, environment)
        : super.findProxyFromEnvironment(url, environment);
  }
}

/// Installs the `dart:io` capture for [engine] and returns a function that
/// takes it out again. Installing twice for the same engine does nothing.
void Function() installWireCapture(FlutwireEngine engine) {
  final current = HttpOverrides.current;
  if (current is FlutwireHttpOverrides && identical(current.engine, engine)) {
    return () {};
  }
  final installed = FlutwireHttpOverrides(engine, previous: current);
  HttpOverrides.global = installed;
  engine.wireCaptureActive = true;
  engine.wireCaptureProbe = () => _stillCaptures(engine);
  return () {
    if (identical(HttpOverrides.current, installed)) {
      HttpOverrides.global = current;
    }
    engine.wireCaptureActive = false;
    engine.wireCaptureProbe = null;
  };
}

/// Whether a client made now would be one of Flutwire's.
///
/// An app's own overrides may sit on top of the capture and still chain to it,
/// so the overrides in force are not enough to tell: the answer is what
/// `HttpClient()` hands out.
bool _stillCaptures(FlutwireEngine engine) {
  final current = HttpOverrides.current;
  if (current is FlutwireHttpOverrides && identical(current.engine, engine)) {
    return true;
  }
  final probe = HttpClient();
  try {
    return probe is FlutwireHttpClient && identical(probe.engine, engine);
  } finally {
    probe.close(force: true);
  }
}

/// An `HttpClient` that records the calls made through it and delegates the
/// work to the client it wraps.
final class FlutwireHttpClient implements HttpClient {
  /// Wraps [_inner], reporting to [_engine]. Every request made through the
  /// client is recorded as a repeat of the call with the id [resentFrom] when
  /// one is given.
  FlutwireHttpClient(this._inner, this._engine, {this.resentFrom});

  final HttpClient _inner;
  final FlutwireEngine _engine;
  final Set<FlutwireCallRecorder> _open = {};
  FlutwireCallRecorder? _last;

  /// The engine this client reports to.
  FlutwireEngine get engine => _engine;

  /// The call this client's requests repeat, if they do.
  final int? resentFrom;

  /// The client this one wraps, without the recording.
  HttpClient get unwrapped => _inner;

  /// The recorder of the latest request opened through this client, which is
  /// null when that request was not recorded.
  FlutwireCallRecorder? get lastRecorder => _last;

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) =>
      _inner.addCredentials(url, realm, c);
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials c,
  ) => _inner.addProxyCredentials(host, port, realm, c);
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? f,
  ) => _inner.badCertificateCallback = f;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  // The signature is the SDK's own, so the return type cannot be spelled out.
  // ignore: inference_failure_on_function_return_type
  set keyLog(Function(String line)? f) => _inner.keyLog = f;

  @override
  void close({bool force = false}) {
    _inner.close(force: force);
    for (final recorder in _open.toList()) {
      recorder.cancel();
    }
    _open.clear();
  }

  Future<HttpClientRequest> _wrap(
    String method,
    Uri url,
    Future<HttpClientRequest> Function() open,
  ) async {
    final recorder = _engine.begin(
      method: method,
      uri: url,
      source: FlutwireSource.io,
      resentFrom: resentFrom,
    );
    _last = recorder;
    final HttpClientRequest request;
    try {
      request = await open();
    } catch (error, stack) {
      recorder?.fail(error, stack);
      rethrow;
    }
    if (recorder == null) return request;
    _open.add(recorder);
    unawaited(recorder.done.then((_) => _open.remove(recorder)));
    return _WireRequest(request, recorder);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _wrap(
    method,
    _uriFor(host, port, path),
    () => _inner.open(method, host, port, path),
  );

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _wrap(method, url, () => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  /// `HttpClient.open` always builds an `http` URL and splits the query and
  /// fragment off the path itself. This does the same so the call is recorded
  /// under the URL the client will really use.
  static Uri _uriFor(String host, int port, String path) {
    final hash = path.indexOf('#');
    final withoutFragment = hash < 0 ? path : path.substring(0, hash);
    final question = withoutFragment.indexOf('?');
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: question < 0
          ? withoutFragment
          : withoutFragment.substring(0, question),
      query: question < 0 ? null : withoutFragment.substring(question + 1),
    );
  }
}

class _WireRequest implements HttpClientRequest {
  _WireRequest(this._inner, this._recorder);

  final HttpClientRequest _inner;
  final FlutwireCallRecorder _recorder;
  Future<HttpClientResponse>? _closing;
  HttpClientResponse? _wrapped;

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;
  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;
  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;
  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  String get method => _inner.method;
  @override
  Uri get uri => _inner.uri;

  @override
  Future<HttpClientResponse> get done => _inner.done.then(_wrap);

  HttpClientResponse _wrap(HttpClientResponse response) =>
      _wrapped ??= _WireResponse(response, _recorder);

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _recorder.cancel();
    _inner.abort(exception, stackTrace);
  }

  @override
  void add(List<int> data) {
    _inner.add(data);
    _recorder.requestBody(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => _inner.addStream(
    stream.map((chunk) {
      _recorder.requestBody(chunk);
      return chunk;
    }),
  );

  @override
  Future<HttpClientResponse> close() => _closing ??= _close();

  Future<HttpClientResponse> _close() async {
    _recorder.requestHeaders(_headersOf(_inner.headers));
    try {
      return _wrap(await _inner.close());
    } catch (error, stack) {
      _recorder.fail(error, stack);
      rethrow;
    }
  }

  @override
  Future<dynamic> flush() => _inner.flush();

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

class _WireResponse extends Stream<List<int>> implements HttpClientResponse {
  _WireResponse(this._inner, this._recorder) {
    _recorder.responseHead(
      statusCode: _inner.statusCode,
      reasonPhrase: _inner.reasonPhrase,
      headers: _headersOf(_inner.headers),
      remoteAddress: _inner.connectionInfo?.remoteAddress.address,
      remotePort: _inner.connectionInfo?.remotePort,
      certificate: _certificateOf(_inner.certificate),
      redirects: [
        for (final hop in _inner.redirects)
          FlutwireRedirect(
            statusCode: hop.statusCode,
            method: hop.method,
            location: hop.location,
          ),
      ],
      compression:
          _inner.compressionState ==
              HttpClientResponseCompressionState.decompressed
          ? 'gzip'
          : null,
    );
  }

  final HttpClientResponse _inner;
  final FlutwireCallRecorder _recorder;

  /// The body as the app reads it: the same bytes, recorded on the way past.
  late final Stream<List<int>> _observed = _recorder.observeResponse(_inner);

  @override
  X509Certificate? get certificate => _inner.certificate;
  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  int get contentLength => _inner.contentLength;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  bool get isRedirect => _inner.isRedirect;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  String get reasonPhrase => _inner.reasonPhrase;
  @override
  List<RedirectInfo> get redirects => _inner.redirects;
  @override
  int get statusCode => _inner.statusCode;

  /// A protocol switch, such as a WebSocket upgrade, hands the socket away. The
  /// call is over as far as HTTP is concerned; the frames are not recorded.
  @override
  Future<Socket> detachSocket() {
    _recorder.complete();
    return _inner.detachSocket();
  }

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => _inner.redirect(method, url, followLoops);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _observed.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

FlutwireHeaders _headersOf(HttpHeaders headers) {
  final fields = <MapEntry<String, String>>[];
  headers.forEach((name, values) {
    for (final value in values) {
      fields.add(MapEntry(name, value));
    }
  });
  return FlutwireHeaders(fields);
}

FlutwireCertificate? _certificateOf(X509Certificate? certificate) {
  if (certificate == null) return null;
  try {
    return FlutwireCertificate(
      subject: certificate.subject,
      issuer: certificate.issuer,
      validFrom: certificate.startValidity,
      validTo: certificate.endValidity,
      sha1: certificate.sha1
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  } on Object {
    return null;
  }
}
