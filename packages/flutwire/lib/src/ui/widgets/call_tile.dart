import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../model/message.dart';
import '../../util/format.dart';
import '../scope.dart';
import '../theme/tokens.dart';
import 'method_chip.dart';
import 'pulse.dart';
import 'status_pill.dart';

/// One row of the list: how a call went, what it was, and how long and how
/// big it was.
class CallTile extends StatelessWidget {
  /// Creates a row for [call].
  const CallTile({
    super.key,
    required this.call,
    required this.now,
    this.selected = false,
    this.selecting = false,
    this.onTap,
    this.onLongPress,
  });

  /// The call to show.
  final FlutwireCall call;

  /// The current time, so every row agrees on how long ago a call was.
  final DateTime now;

  /// Whether the row is part of the selection.
  final bool selected;

  /// Whether a selection is in progress, which puts a tick where the status is.
  final bool selecting;

  /// Opens the call.
  final VoidCallback? onTap;

  /// Starts or extends a selection.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final title = call.graphql?.operationName ?? _path(call);
    final slow = call.duration.inMilliseconds;
    // A conversation lasts as long as its two sides have something to say, so
    // its length says nothing about how slow it was.
    final durationColor = call.isPending
        ? t.copperTone
        : call.messages != null
        ? t.muted
        : slow >= 3000
        ? t.error
        : slow >= 1000
        ? t.warning
        : t.muted;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? t.raised : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected && !selecting
                      ? FlutwireTokens.copper
                      : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: t.line),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 50,
                  child: selecting
                      ? Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: selected ? t.copperTone : t.faint,
                            size: 26,
                          ),
                        )
                      : StatusPill(call: call),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MethodChip(call.method),
                          if (call.graphql != null) ...[
                            const SizedBox(width: 6),
                            _Badge('GQL', t.copperTone),
                          ],
                          if (call.messages case final messages?) ...[
                            const SizedBox(width: 6),
                            _Badge(
                              messages.kind ==
                                      FlutwireConversationKind.eventStream
                                  ? 'SSE'
                                  : 'WS',
                              t.info,
                            ),
                          ],
                          if (call.resentFrom != null) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.replay_rounded,
                              size: 13,
                              color: t.copperTone,
                              semanticLabel: context.strings.resentBadge,
                            ),
                          ],
                          if (call.pinned) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: t.warning,
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.mono(
                                size: 13,
                                weight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${call.host}  ·  ${formatAgo(call.startedAt, now)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body(size: 12, color: t.muted),
                      ),
                      if (call.state == FlutwireCallState.failed &&
                          call.error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          call.error!.type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.mono(size: 11, color: t.error),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Pulse(
                      active: call.isPending,
                      child: Text(
                        call.isPending
                            ? formatDuration(call.duration)
                            : formatDuration(call.duration),
                        style: t.mono(size: 12, color: durationColor),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatBytes(call.responseSize),
                      style: t.mono(size: 11, color: t.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _path(FlutwireCall call) {
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return call.uri.hasQuery ? '$path?${call.uri.query}' : path;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: t.mono(
          size: 9.5,
          weight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
      ),
    );
  }
}
