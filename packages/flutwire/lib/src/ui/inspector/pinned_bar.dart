import 'package:flutter/material.dart';

/// A bar that stays at the top of the list while the calls scroll under it.
class PinnedBar extends SliverPersistentHeaderDelegate {
  /// Creates a bar [height] tall that draws what [builder] returns.
  PinnedBar({required this.height, required this.builder});

  /// How tall the bar is. It neither grows nor shrinks.
  final double height;

  /// Draws the bar. [overlapsContent] is true once the list scrolls under it.
  final Widget Function(BuildContext context, {required bool overlapsContent})
  builder;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => builder(context, overlapsContent: overlapsContent);

  // The builder closes over the page's state, so there is no cheaper way to
  // know whether what it draws has changed.
  @override
  bool shouldRebuild(PinnedBar oldDelegate) => true;
}
