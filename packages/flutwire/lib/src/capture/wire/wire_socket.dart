import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../model/message.dart';
import '../messages/websocket_reader.dart';
import '../recorder.dart';

/// A socket that was an HTTP connection and became a WebSocket. It hands the
/// bytes through unchanged, in both directions, while a reader on each side
/// finds the frames and reports them to the recorder of the call.
///
/// The call stays open for as long as the connection does. It ends when both
/// sides have sent a close frame, when the other side stops sending, when the
/// socket is destroyed, or when it fails.
final class WireSocket extends Stream<Uint8List> implements Socket {
  /// Wraps [_inner], reporting the messages that cross it to [_recorder].
  /// [deflate] is what the handshake agreed about compression.
  WireSocket(this._inner, this._recorder, {WebSocketDeflate? deflate}) {
    _recorder.startConversation(FlutwireConversationKind.webSocket);
    _incoming = _reader(
      sent: false,
      deflate: deflate != null,
      noContextTakeover: deflate?.serverNoContextTakeover ?? false,
    );
    _outgoing = _reader(
      sent: true,
      deflate: deflate != null,
      noContextTakeover: deflate?.clientNoContextTakeover ?? false,
    );
    // `done` is the end of the writing side, which closing the sink reaches
    // while the other side may still be saying goodbye, so only a failure ends
    // the conversation here.
    unawaited(
      _inner.done.then(
        (_) {},
        onError: (Object error, StackTrace stack) =>
            _recorder.fail(error, stack),
      ),
    );
  }

  final Socket _inner;
  final FlutwireCallRecorder _recorder;
  late final WebSocketReader _incoming;
  late final WebSocketReader _outgoing;
  bool _closeSent = false;
  bool _closeReceived = false;

  WebSocketReader _reader({
    required bool sent,
    required bool deflate,
    required bool noContextTakeover,
  }) => WebSocketReader(
    onMessage: (kind, payload, total, {required undecoded}) {
      _recorder.message(
        sent: sent,
        kind: kind,
        payload: payload,
        totalBytes: total,
        undecoded: undecoded,
      );
      if (kind != FlutwireMessageKind.close) return;
      // The closing handshake is over once each side has said goodbye, which
      // is before the connection itself goes away, if it ever does.
      if (sent) {
        _closeSent = true;
      } else {
        _closeReceived = true;
      }
      if (_closeSent && _closeReceived) _recorder.complete();
    },
    deflate: deflate,
    noContextTakeover: noContextTakeover,
  );

  /// The bytes as the app reads them: the same, seen on the way past.
  late final Stream<Uint8List> _tapped = _inner.transform(
    StreamTransformer<Uint8List, Uint8List>.fromHandlers(
      handleData: (chunk, sink) {
        _incoming.add(chunk);
        sink.add(chunk);
      },
      handleError: (error, stack, sink) {
        _recorder.fail(error, stack);
        sink.addError(error, stack);
      },
      handleDone: (sink) {
        _recorder.complete();
        sink.close();
      },
    ),
  );

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _tapped.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void add(List<int> data) {
    _outgoing.add(data);
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) => _inner.addStream(
    stream.map((chunk) {
      _outgoing.add(chunk);
      return chunk;
    }),
  );

  @override
  Future<dynamic> close() => _inner.close();

  @override
  Future<dynamic> get done => _inner.done;

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

  @override
  InternetAddress get address => _inner.address;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get port => _inner.port;

  @override
  int get remotePort => _inner.remotePort;

  @override
  void destroy() {
    _inner.destroy();
    _recorder.complete();
  }

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}
