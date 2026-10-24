import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../session.dart';
import 'inspector/inspector_page.dart';
import 'shell.dart';

/// Puts the inspector on screen above the app.
///
/// The inspector is a route on the app's own navigator, so that Back leaves it
/// and the app underneath is left alone.
final class InspectorLauncher {
  /// Creates a launcher that looks for a navigator in [navigatorKey] first.
  InspectorLauncher(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;
  final ValueNotifier<bool> _isOpen = ValueNotifier(false);
  Timer? _waiting;

  /// Whether the inspector is on screen.
  ValueListenable<bool> get isOpen => _isOpen;

  /// Opens the inspector for [session].
  ///
  /// It goes into the panel beside the app when the user left it there, and
  /// otherwise onto the screen. With a [context] the navigator above it is
  /// used. Without one, the navigator from the key, or else the outermost one
  /// in the widget tree. Does nothing if the inspector is already open or there
  /// is no navigator.
  Future<void> open(FlutwireSession session, [BuildContext? context]) async {
    if (_isOpen.value || session.dock.isOpen) return;
    if (session.dock.wantsDock) {
      session.dock.open();
      return;
    }
    final navigator = context != null
        ? Navigator.maybeOf(context, rootNavigator: true)
        : (_navigatorKey.currentState ?? _outermostNavigator());
    if (navigator == null) return;
    _isOpen.value = true;
    try {
      await navigator.push(
        shellRoute(session, name: 'flutwire', child: const InspectorPage()),
      );
    } finally {
      _isOpen.value = false;
    }
  }

  /// Opens the inspector as soon as the app has a navigator. A cold start from
  /// the notification gets here before the first screen is up, so this keeps
  /// looking for a while and then gives up.
  void openWhenReady(FlutwireSession session) {
    _waiting?.cancel();
    var attempts = 0;
    _waiting = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      attempts++;
      if (_navigatorKey.currentState != null || _outermostNavigator() != null) {
        timer.cancel();
        unawaited(open(session));
      } else if (attempts > 100) {
        timer.cancel();
      }
    });
  }

  /// Stops waiting and releases the listeners.
  void dispose() {
    _waiting?.cancel();
    _isOpen.dispose();
  }

  static NavigatorState? _outermostNavigator() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }
}
