import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/body.dart';
import '../../model/call.dart';
import '../../model/message.dart';
import '../../util/format.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/segmented_control.dart';
import 'body_pane.dart';

enum _Direction { all, sent, received }

/// The messages of a WebSocket, or the events of a server-sent event stream, in
/// the order they crossed, with the moment each one did.
///
/// While the call runs the list follows the newest message, until the reader
/// scrolls up to look at an older one.
class MessagesTab extends StatefulWidget {
  /// Creates the tab for [call], which must hold messages.
  const MessagesTab({super.key, required this.call});

  /// The call whose messages are listed.
  final FlutwireCall call;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  final ScrollController _scroll = ScrollController();
  _Direction _direction = _Direction.all;
  bool _following = true;

  FlutwireMessages get _messages => widget.call.messages!;

  @override
  void initState() {
    super.initState();
    // A conversation that is still going is read from its end, a finished one
    // from its start.
    if (widget.call.isPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toNewest());
    }
  }

  @override
  void didUpdateWidget(MessagesTab old) {
    super.didUpdateWidget(old);
    if (_following && widget.call.messages!.total != old.call.messages!.total) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toNewest());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toNewest() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    // Reading an older message turns following off, and the end turns it on.
    _following = notification.metrics.extentAfter < 48;
    return false;
  }

  List<FlutwireMessage> get _shown => switch (_direction) {
    _Direction.all => _messages.items,
    _Direction.sent => [
      for (final m in _messages.items)
        if (m.sent) m,
    ],
    _Direction.received => [
      for (final m in _messages.items)
        if (!m.sent) m,
    ],
  };

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final events = _messages.kind == FlutwireConversationKind.eventStream;
    final shown = _shown;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              events
                  ? s.eventCount(_messages.total)
                  : s.messageCount(_messages.total),
              style: t.body(size: 13, color: t.muted),
            ),
          ),
        ),
        // An event stream only goes one way, so there is nothing to tell apart.
        if (!events)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedControl<_Direction>(
              options: {
                _Direction.all: s.messagesAll,
                _Direction.sent: s.messagesSent,
                _Direction.received: s.messagesReceived,
              },
              value: _direction,
              onChanged: (value) => setState(() => _direction = value),
            ),
          ),
        if (_messages.dropped > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                s.messagesDropped(_messages.dropped),
                style: t.body(size: 12, color: t.faint),
              ),
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Text(s.messagesEmpty, style: t.body(color: t.faint)),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _scrolled,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: shown.length,
                    itemBuilder: (context, index) =>
                        _MessageTile(call: widget.call, message: shown[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.call, required this.message});

  final FlutwireCall call;
  final FlutwireMessage message;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final preview = message.preview;
    final color = message.sent ? t.copperTone : t.ok;
    return InkWell(
      onTap: () => unawaited(_openMessage(context, call, message)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              message.sent
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 18,
              color: color,
              semanticLabel: message.sent ? s.messagesSent : s.messagesReceived,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      message.event ?? s.messageKind(message.kind),
                      formatBytes(message.totalBytes),
                    ].join('  ·  '),
                    style: t.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.mono(size: 12.5, color: t.ink),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '+${formatDuration(message.at.difference(call.startedAt))}',
              style: t.mono(size: 11.5, color: t.faint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [message] in a sheet over the call: its payload in the viewer that fits
/// it, so a JSON message is a tree.
Future<void> _openMessage(
  BuildContext context,
  FlutwireCall call,
  FlutwireMessage message,
) {
  final session = context.session;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    builder: (_) => FlutwireShell(
      session: session,
      child: _MessageSheet(call: call, message: message),
    ),
  );
}

class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.call, required this.message});

  final FlutwireCall call;
  final FlutwireMessage message;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FlutwireTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: t.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                [
                  message.sent ? s.messagesSent : s.messagesReceived,
                  message.event ?? s.messageKind(message.kind),
                  formatBytes(message.totalBytes),
                ].join('  ·  '),
                style: t.body(size: 15, weight: FontWeight.w600, color: t.ink),
              ),
            ),
            if (message.undecoded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  s.messageUndecoded,
                  style: t.body(size: 12.5, color: t.warning),
                ),
              ),
            SizedBox(height: height * 0.55, child: _payload(context)),
          ],
        ),
      ),
    );
  }

  Widget _payload(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    if (message.kind == FlutwireMessageKind.close) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SelectableText(
          message.preview.isEmpty ? s.messageNoPayload : message.preview,
          style: t.mono(size: 13, color: t.ink),
        ),
      );
    }
    if (message.bytes.isEmpty) {
      return Center(
        child: Text(s.messageNoPayload, style: t.body(color: t.faint)),
      );
    }
    return BodyPane(
      call: call,
      body: FlutwireBody(
        bytes: message.bytes,
        totalBytes: message.totalBytes,
        contentType: message.kind == FlutwireMessageKind.binary
            ? 'application/octet-stream'
            : null,
      ),
      isRequest: message.sent,
    );
  }
}
