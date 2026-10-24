import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/headers.dart';

/// A request that is on hold at a breakpoint: what the app asked for, which has
/// not left yet.
@immutable
final class FlutwireHeldRequest {
  /// Creates a held request.
  const FlutwireHeldRequest({
    required this.id,
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.since,
    this.rule,
  });

  /// Names the request while it is held.
  final int id;

  /// The method.
  final String method;

  /// Where the request goes.
  final Uri uri;

  /// The header fields, as the app set them and as they would go out, which
  /// are not hidden: this is the real request.
  final FlutwireHeaders headers;

  /// The whole body.
  final Uint8List body;

  /// When the request was stopped.
  final DateTime since;

  /// The label of the breakpoint that stopped it.
  final String? rule;

  /// A copy with the given parts replaced.
  FlutwireHeldRequest copyWith({
    String? method,
    Uri? uri,
    FlutwireHeaders? headers,
    Uint8List? body,
  }) => FlutwireHeldRequest(
    id: id,
    method: method ?? this.method,
    uri: uri ?? this.uri,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    since: since,
    rule: rule,
  );

  /// Whether [other] asks for the same thing: the method, the address, the
  /// header fields and the body.
  bool sameRequestAs(FlutwireHeldRequest other) =>
      method == other.method &&
      uri == other.uri &&
      headers == other.headers &&
      listEquals(body, other.body);
}

/// A request that was put on hold: its number, and what becomes of it.
@immutable
final class FlutwireHoldTicket {
  /// Creates a ticket.
  const FlutwireHoldTicket(this.id, this.answer);

  /// The number the held request has while it waits.
  final int id;

  /// Completes when the request is let go: with the request to send, which may
  /// have been changed, or with null when it was stopped.
  final Future<FlutwireHeldRequest?> answer;
}

/// The requests that are held at breakpoints, until somebody sends them on or
/// stops them.
///
/// A request waits here for as long as it takes. The app's own call is waiting
/// too, so whoever holds a request is holding up the app.
final class FlutwireBreakpoints extends ChangeNotifier {
  final Map<int, _Hold> _holds = {};
  final Set<int> _claimed = {};
  int _last = 0;
  bool _disposed = false;

  /// Called with each request as it is held, so that the inspector can come
  /// forward.
  void Function(FlutwireHeldRequest request)? onHeld;

  /// The requests that are held, the oldest first.
  List<FlutwireHeldRequest> get held => [
    for (final hold in _holds.values) hold.request,
  ];

  /// Whether any request is held.
  bool get isHolding => _holds.isNotEmpty;

  /// The held request with [id], or null.
  FlutwireHeldRequest? find(int id) => _holds[id]?.request;

  /// Holds the request described by the arguments. The ticket it gives back
  /// says when the request is let go: with the request to send, which may have
  /// been changed, or with null when it was stopped.
  FlutwireHoldTicket hold({
    required String method,
    required Uri uri,
    required FlutwireHeaders headers,
    required Uint8List body,
    String? rule,
    DateTime? now,
  }) {
    if (_disposed) return FlutwireHoldTicket(0, Future.value());
    final request = FlutwireHeldRequest(
      id: ++_last,
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      since: now ?? DateTime.now(),
      rule: rule,
    );
    final hold = _Hold(request);
    _holds[request.id] = hold;
    notifyListeners();
    onHeld?.call(request);
    return FlutwireHoldTicket(request.id, hold.completer.future);
  }

  /// Says that somebody is looking at the held request with [id], and whether
  /// that is news: it is the first time anybody said so. It lets the inspector
  /// open the editor of a request once, however many screens could.
  bool claim(int id) => _holds.containsKey(id) && _claimed.add(id);

  /// Lets the request with [id] go as [edited], which has its id and may differ
  /// from what was held in anything else.
  void resume(int id, FlutwireHeldRequest edited) => _release(id, edited);

  /// Lets the request with [id] go as it was held.
  void resumeUnchanged(int id) => _release(id, _holds[id]?.request);

  /// Stops the request with [id]: the app's call fails.
  void stop(int id) => _release(id, null);

  /// Stops every request that is held.
  void stopAll() {
    for (final id in _holds.keys.toList()) {
      _release(id, null);
    }
  }

  void _release(int id, FlutwireHeldRequest? answer) {
    final hold = _holds.remove(id);
    if (hold == null) return;
    _claimed.remove(id);
    hold.completer.complete(answer);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    stopAll();
    _disposed = true;
    super.dispose();
  }
}

class _Hold {
  _Hold(this.request);

  final FlutwireHeldRequest request;
  final Completer<FlutwireHeldRequest?> completer = Completer();
}
