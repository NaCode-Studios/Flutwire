import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Scrolls a lazily built list to a row whose height is not known in advance.
///
/// The fields and the parts lists wrap their text, so rows differ in height and
/// the offset of a row cannot be computed. The list gives the row it wants
/// shown a key; when that row is built the revealer scrolls it into view, and
/// when it is not built yet the revealer jumps to where the row should be, on
/// average, and looks again once the rows around it exist.
final class RowRevealer {
  /// Creates a revealer for the list scrolled by [controller].
  RowRevealer(this.controller);

  /// The controller of the list.
  final ScrollController controller;

  /// The key the row being revealed must carry.
  final GlobalKey key = GlobalKey();

  int _target = -1;

  /// The row being revealed, or -1.
  int get target => _target;

  /// The key to give the row at [row]: the shared key if it is the target.
  Key? keyFor(int row) => row == _target ? key : null;

  /// Makes [row] the target and brings it into view once it is built.
  ///
  /// [itemCount] is the number of rows in the list. [isMounted] tells the
  /// revealer when its owner is gone, so that it stops trying.
  void reveal(
    int row, {
    required int itemCount,
    required bool Function() isMounted,
  }) {
    _target = row;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _attempt(row, itemCount, isMounted, 0),
    );
  }

  /// Forgets the target.
  void clear() => _target = -1;

  void _attempt(int row, int itemCount, bool Function() isMounted, int tries) {
    if (!isMounted() || row != _target) return;
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.35);
      return;
    }
    if (tries >= 4 || !controller.hasClients || itemCount == 0) return;
    final position = controller.position;
    final average =
        (position.maxScrollExtent + position.viewportDimension) / itemCount;
    controller.jumpTo(
      math.min(
        math.max(
          row * average - position.viewportDimension / 2,
          position.minScrollExtent,
        ),
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _attempt(row, itemCount, isMounted, tries + 1),
    );
  }
}
