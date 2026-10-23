import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../platform/native.dart';
import '../../session.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/mark.dart';

/// Floats a small button above the app that opens the inspector, and listens
/// for the keyboard shortcut that does the same.
///
/// It is for places without a notification in the shade: the web, Windows and
/// Linux. Give it to the app through its builder:
///
/// ```dart
/// MaterialApp(builder: Flutwire.builder, ...)
/// ```
///
/// By default it shows only where there is no notification, and it hides
/// itself while the inspector is open. [FlutwireConfig.floatingButton] changes
/// when it shows. The shortcut, Ctrl or Cmd with Shift and L, works whether the
/// button shows or not.
class FlutwireOverlay extends StatefulWidget {
  /// Puts the button above [child], for as long as [session] holds a running
  /// Flutwire.
  const FlutwireOverlay({
    super.key,
    required this.session,
    required this.child,
  });

  /// The running session, or null while Flutwire is not recording. The button
  /// and the shortcut appear when one arrives.
  final ValueListenable<FlutwireSession?> session;

  /// The app.
  final Widget child;

  @override
  State<FlutwireOverlay> createState() => _FlutwireOverlayState();
}

class _FlutwireOverlayState extends State<FlutwireOverlay> {
  // How far the button sits from the right and bottom edges of the screen.
  double _right = 16;
  double _bottom = 24;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final session = widget.session.value;
    if (event is! KeyDownEvent || session == null) return false;
    final keyboard = HardwareKeyboard.instance;
    final chord =
        event.logicalKey == LogicalKeyboardKey.keyL &&
        keyboard.isShiftPressed &&
        (keyboard.isControlPressed || keyboard.isMetaPressed);
    if (!chord) return false;
    unawaited(session.openInspector());
    return true;
  }

  bool _shown(FlutwireSession session) {
    final config = session.config;
    return switch (config.floatingButton) {
      FlutwireButtonMode.never => false,
      FlutwireButtonMode.always => true,
      FlutwireButtonMode.auto =>
        !config.notification.enabled ||
            session.notificationPermission.value ==
                FlutwireNotificationPermission.unsupported,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        ValueListenableBuilder<FlutwireSession?>(
          valueListenable: widget.session,
          builder: (context, session, _) =>
              session == null ? const SizedBox.shrink() : _floating(session),
        ),
      ],
    );
  }

  Widget _floating(FlutwireSession session) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        session.inspectorOpen,
        session.notificationPermission,
      ]),
      builder: (context, _) {
        if (session.inspectorOpen.value || !_shown(session)) {
          return const SizedBox.shrink();
        }
        final screen = MediaQuery.sizeOf(context);
        final inset = MediaQuery.paddingOf(context);
        return Positioned(
          right: _right.clamp(0, screen.width - 56) + inset.right,
          bottom: _bottom.clamp(0, screen.height - 56) + inset.bottom,
          child: GestureDetector(
            onPanUpdate: (drag) => setState(() {
              _right -= drag.delta.dx;
              _bottom -= drag.delta.dy;
            }),
            child: FlutwireShell(
              session: session,
              systemUi: false,
              child: const _Button(),
            ),
          ),
        );
      },
    );
  }
}

class _Button extends StatelessWidget {
  const _Button();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return Semantics(
      button: true,
      label: s.shortcutLabel,
      child: Material(
        key: const ValueKey('flutwire.button'),
        color: t.raised,
        elevation: 4,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          side: BorderSide(color: t.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          onTap: () => unawaited(session.openInspector()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            // The count follows the history by itself: this widget is const,
            // so its parent rebuilding would not reach it.
            child: ValueListenableBuilder(
              valueListenable: session.store.calls,
              builder: (context, calls, _) {
                final failed = calls.where((c) => c.isError).length;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FlutwireMark(size: 18, color: t.ink),
                    const SizedBox(width: 8),
                    Text(
                      '${calls.length}',
                      style: t.mono(
                        size: 13,
                        weight: FontWeight.w600,
                        color: t.ink,
                        height: 1.2,
                      ),
                    ),
                    if (failed > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
