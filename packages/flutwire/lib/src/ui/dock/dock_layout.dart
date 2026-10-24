import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dock.dart';
import '../../session.dart';
import '../inspector/inspector_page.dart';
import '../scope.dart';
import '../shell.dart';

/// Lays out the app and, while the dock is open, the inspector beside it.
///
/// The app is always laid out the same way, in the first place of the same
/// row or column, so docking and undocking the inspector never rebuilds it and
/// the app keeps its state. The space it is left with is what its
/// `MediaQuery` reports, so it answers to the smaller screen.
class DockLayout extends StatefulWidget {
  /// Lays out [app], with room for the inspector of [session] when it has one
  /// that is docked.
  const DockLayout({super.key, required this.session, required this.app});

  /// The running session, or null while Flutwire is not recording.
  final FlutwireSession? session;

  /// The app.
  final Widget app;

  /// The width of the strip the panel is resized from.
  static const double handleExtent = 16;

  @override
  State<DockLayout> createState() => _DockLayoutState();
}

class _DockLayoutState extends State<DockLayout> {
  VoidCallback? _detach;

  @override
  void initState() {
    super.initState();
    _detach = widget.session?.dock.attachHost();
  }

  @override
  void didUpdateWidget(DockLayout old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      _detach?.call();
      _detach = widget.session?.dock.attachHost();
    }
  }

  @override
  void dispose() {
    _detach?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return LayoutBuilder(
      builder: (context, box) {
        final media = MediaQuery.of(context);
        if (session == null) return _flex(media, box, null);
        return ListenableBuilder(
          listenable: session.dock,
          builder: (context, _) => _flex(media, box, session),
        );
      },
    );
  }

  Widget _flex(MediaQueryData media, BoxConstraints box, FlutwireSession? s) {
    final dock = s?.dock;
    final open = dock != null && dock.isOpen;
    final side = dock?.sideFor(box.biggest) ?? FlutwireDockSide.bottom;
    final horizontal = side == FlutwireDockSide.right;
    final total = horizontal ? box.maxWidth : box.maxHeight;
    final panel = open ? _panelExtent(total, dock.extent, horizontal) : 0.0;
    final taken = open ? panel + DockLayout.handleExtent : 0.0;
    final appSize = horizontal
        ? Size(box.maxWidth - taken, box.maxHeight)
        : Size(box.maxWidth, box.maxHeight - taken);
    // What touches the edge of the screen keeps the room the system asks for.
    final appMedia = media
        .copyWith(size: appSize)
        .removePadding(
          removeRight: open && horizontal,
          removeBottom: open && !horizontal,
        );
    return Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      // The panel is on the right whichever way the language runs.
      textDirection: TextDirection.ltr,
      children: [
        Expanded(
          child: MediaQuery(data: appMedia, child: widget.app),
        ),
        if (open) ...[
          FlutwireShell(
            session: s!,
            systemUi: false,
            child: _Handle(dock: dock, horizontal: horizontal, total: total),
          ),
          SizedBox(
            width: horizontal ? panel : null,
            height: horizontal ? null : panel,
            child: _Panel(
              session: s,
              media: media
                  .copyWith(
                    size: horizontal
                        ? Size(panel, box.maxHeight)
                        : Size(box.maxWidth, panel),
                  )
                  .removePadding(
                    removeLeft: horizontal,
                    removeTop: !horizontal,
                  ),
            ),
          ),
        ],
      ],
    );
  }

  /// How much of [total] the panel takes: its share, but never so little that
  /// it cannot be used or so much that the app disappears.
  static double _panelExtent(double total, double share, bool horizontal) {
    final least = math.min(horizontal ? 280.0 : 180.0, total * 0.5);
    final leastApp = math.min(160.0, total * 0.3);
    final most = math.max(least, total - DockLayout.handleExtent - leastApp);
    return (total * share).clamp(least, most);
  }
}

/// The inspector, with a navigator of its own, so that a call opens inside the
/// panel and Back stays there.
class _Panel extends StatelessWidget {
  const _Panel({required this.session, required this.media});

  final FlutwireSession session;
  final MediaQueryData media;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: media,
      child: FlutwireShell(
        session: session,
        systemUi: false,
        child: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'flutwire/dock'),
              builder: (_) => const InspectorPage(docked: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip between the app and the panel, which is dragged to resize it.
class _Handle extends StatelessWidget {
  const _Handle({
    required this.dock,
    required this.horizontal,
    required this.total,
  });

  final FlutwireDock dock;
  final bool horizontal;
  final double total;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return Semantics(
      label: s.dockResize,
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey('flutwire.dock.handle'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: horizontal
              ? (drag) => dock.resizeBy(-drag.delta.dx / total)
              : null,
          onVerticalDragUpdate: horizontal
              ? null
              : (drag) => dock.resizeBy(-drag.delta.dy / total),
          onHorizontalDragEnd: horizontal ? (_) => dock.keepSize() : null,
          onVerticalDragEnd: horizontal ? null : (_) => dock.keepSize(),
          child: Container(
            width: horizontal ? DockLayout.handleExtent : null,
            height: horizontal ? null : DockLayout.handleExtent,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              border: Border(
                left: horizontal
                    ? BorderSide(color: t.lineStrong)
                    : BorderSide.none,
                top: horizontal
                    ? BorderSide.none
                    : BorderSide(color: t.lineStrong),
              ),
            ),
            child: Container(
              width: horizontal ? 4 : 36,
              height: horizontal ? 36 : 4,
              decoration: BoxDecoration(
                color: t.lineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
