import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../scope.dart';
import 'pulse.dart';

/// The status of a call as a pill: the code, or a short word when there is none.
class StatusPill extends StatelessWidget {
  /// Creates a pill for [call]. [large] is the size used in the detail header.
  const StatusPill({super.key, required this.call, this.large = false});

  /// The call it describes.
  final FlutwireCall call;

  /// Whether to draw the bigger variant.
  final bool large;

  /// The text a pill shows for [call].
  static String labelFor(FlutwireCall call) => switch (call.state) {
    FlutwireCallState.pending =>
      call.statusCode == null ? '···' : '${call.statusCode}',
    FlutwireCallState.failed => 'ERR',
    FlutwireCallState.cancelled => 'CXL',
    FlutwireCallState.completed => '${call.statusCode ?? '---'}',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final color = t.statusColor(call);
    final pill = Container(
      constraints: BoxConstraints(minWidth: large ? 60 : 46),
      height: large ? 34 : 28,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8),
      decoration: BoxDecoration(
        color: t.tint(color),
        borderRadius: BorderRadius.circular(large ? 12 : 10),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Text(
        labelFor(call),
        style: t.mono(
          size: large ? 15 : 12.5,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
    return call.isPending ? Pulse(child: pill) : pill;
  }
}
