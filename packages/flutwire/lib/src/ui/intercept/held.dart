import 'package:flutter/widgets.dart' show Route;

import '../../intercept/breakpoints.dart';
import '../../model/body.dart';
import '../../model/call.dart';
import '../../session.dart';
import '../resend/resend_page.dart';
import '../shell.dart';

/// The route of the editor of a request that a breakpoint holds.
Route<void> heldRoute(FlutwireSession session, FlutwireHeldRequest held) =>
    shellRoute(
      session,
      name: 'flutwire/held',
      child: ResendPage(call: _asCall(held), held: held),
    );

/// The held request in the shape the editor starts from: a call that has only
/// its request. Nothing in it was hidden, because it was never recorded.
FlutwireCall _asCall(FlutwireHeldRequest held) => FlutwireCall(
  id: held.id,
  method: held.method,
  uri: held.uri,
  source: FlutwireSource.io,
  startedAt: held.since,
  request: FlutwireRequest(
    headers: held.headers,
    body: FlutwireBody(bytes: held.body, contentType: held.headers.contentType),
  ),
);
