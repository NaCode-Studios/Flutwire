import 'dart:async';

import 'package:flutter/material.dart';

import '../../export/export.dart';
import '../../model/call.dart';
import '../../model/cookies.dart';
import '../../model/headers.dart';
import '../../model/message.dart';
import '../../store/store.dart';
import '../../util/format.dart';
import '../actions.dart';
import '../compare/compare_page.dart';
import '../resend/resend_page.dart';
import '../scope.dart';
import '../shell.dart';
import '../widgets/method_chip.dart';
import '../widgets/segmented_control.dart';
import '../widgets/status_pill.dart';
import '../widgets/wire_rule.dart';
import 'body_pane.dart';
import 'cookies_view.dart';
import 'headers_view.dart';
import 'messages_tab.dart';
import 'overview_tab.dart';

enum _Tab { overview, request, response, messages }

enum _Part { body, headers, cookies }

/// One call in full: an overview, then the request and the response, each as a
/// body, header fields and cookies.
///
/// The page follows the call while it runs, so a response that is still
/// arriving fills in as it comes.
class CallDetailPage extends StatefulWidget {
  /// Opens the call with [callId]. [embedded] drops the back button, for the
  /// two-pane layout on a wide screen.
  const CallDetailPage({
    super.key,
    required this.callId,
    this.embedded = false,
  });

  /// The id of the call to show.
  final int callId;

  /// Whether the page sits beside the list instead of on top of it.
  final bool embedded;

  @override
  State<CallDetailPage> createState() => _CallDetailPageState();
}

class _CallDetailPageState extends State<CallDetailPage> {
  late final FlutwireStore _store;
  FlutwireCall? _call;
  bool _gone = false;
  _Tab _tab = _Tab.overview;
  _Part _requestPart = _Part.body;
  _Part _responsePart = _Part.body;
  Timer? _refresh;
  FlutwireCall? _lastSeen;

  @override
  void initState() {
    super.initState();
    _store = context.session.store;
    _store.calls.addListener(_historyChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _store.calls.removeListener(_historyChanged);
    _refresh?.cancel();
    super.dispose();
  }

  void _historyChanged() {
    final latest = _store.find(widget.callId);
    if (latest == null) {
      if (mounted && _call != null) setState(() => _gone = true);
      return;
    }
    if (identical(latest, _lastSeen)) return;
    // A burst of progress updates is read once.
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 150), _load);
  }

  Future<void> _load() async {
    final summary = _store.find(widget.callId);
    final full = await _store.load(widget.callId);
    if (!mounted) return;
    setState(() {
      _lastSeen = summary;
      _call = full;
      _gone = full == null;
    });
  }

  void _openCall(int id) {
    unawaited(
      Navigator.of(context).push(
        shellRoute(
          context.session,
          name: 'flutwire/call',
          child: CallDetailPage(callId: id),
        ),
      ),
    );
  }

  /// Sets the call this one repeats beside it, the original on the left.
  void _compareWith(int originalId) {
    unawaited(
      Navigator.of(context).push(
        shellRoute(
          context.session,
          name: 'flutwire/compare',
          child: ComparePage(leftId: originalId, rightId: widget.callId),
        ),
      ),
    );
  }

  Future<void> _togglePin(FlutwireCall call) async {
    await _store.setPinned([call.id], pinned: !call.pinned);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final call = _call;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          call == null ? '' : '${call.method}  ${call.host}',
          style: t.mono(size: 14, weight: FontWeight.w600, color: t.ink),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(WireRule.height),
          child: WireRule(),
        ),
        actions: call == null ? null : _actions(context, call),
      ),
      body: _gone
          ? Center(
              child: Text(s.callGone, style: t.body(color: t.faint)),
            )
          : call == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              children: [
                _Header(call: call),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: SegmentedControl<_Tab>(
                    options: {
                      _Tab.overview: s.tabOverview,
                      _Tab.request: s.tabRequest,
                      _Tab.response: s.tabResponse,
                      if (call.messages case final messages?)
                        _Tab.messages:
                            messages.kind ==
                                FlutwireConversationKind.eventStream
                            ? s.tabEvents
                            : s.tabMessages,
                    },
                    value: _tab,
                    onChanged: (v) => setState(() => _tab = v),
                  ),
                ),
                Expanded(child: _content(context, call)),
              ],
            ),
    );
  }

  List<Widget> _actions(BuildContext context, FlutwireCall call) {
    final s = context.strings;
    final session = context.session;
    return [
      // A callable function travels through the native SDK, which adds
      // credentials Flutwire never sees, and a WebSocket handshake is not a
      // request that can be sent on its own, so neither is sent again from here.
      if (session.canResend &&
          call.source != FlutwireSource.functions &&
          call.messages?.kind != FlutwireConversationKind.webSocket)
        IconButton(
          tooltip: s.resend,
          icon: const Icon(Icons.replay_rounded),
          onPressed: () => unawaited(
            Navigator.of(context).push(
              shellRoute(
                session,
                name: 'flutwire/resend',
                child: ResendPage(call: call),
              ),
            ),
          ),
        ),
      IconButton(
        tooltip: call.pinned ? s.unpin : s.pin,
        icon: Icon(
          call.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          color: call.pinned ? context.fw.warning : null,
        ),
        onPressed: () => _togglePin(call),
      ),
      // Each entry carries what it does, so the menu is one list.
      PopupMenuButton<VoidCallback>(
        tooltip: s.share,
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => action(),
        itemBuilder: (menu) => [
          PopupMenuItem(
            value: () => unawaited(copyText(context, call.uri.toString())),
            child: Text(s.copyUrl),
          ),
          PopupMenuItem(
            value: () => unawaited(copyCurl(context, call)),
            child: Text(s.copyCurl),
          ),
          const PopupMenuDivider(),
          for (final (format, label) in [
            (FlutwireExportFormat.text, s.shareAsText),
            (FlutwireExportFormat.curl, s.shareAsCurl),
            (FlutwireExportFormat.har, s.shareAsHar),
            (FlutwireExportFormat.json, s.shareAsJson),
          ])
            PopupMenuItem(
              value: () => unawaited(shareCalls(context, [call], format)),
              child: Text(label),
            ),
        ],
      ),
    ];
  }

  Widget _content(BuildContext context, FlutwireCall call) {
    final s = context.strings;
    switch (_tab) {
      case _Tab.overview:
        return OverviewTab(
          call: call,
          onOpenCall: _openCall,
          onCompare: _compareWith,
        );
      case _Tab.messages:
        return call.messages == null
            ? OverviewTab(
                call: call,
                onOpenCall: _openCall,
                onCompare: _compareWith,
              )
            : MessagesTab(call: call);
      case _Tab.request:
        final cookies = [
          for (final line in call.request.headers['cookie'])
            ...parseCookieHeader(line),
        ];
        return _Side(
          parts: {
            _Part.body: s.tabBody,
            _Part.headers: s.tabHeaders,
            if (cookies.isNotEmpty) _Part.cookies: s.tabCookies,
          },
          value: _requestPart,
          onChanged: (v) => setState(() => _requestPart = v),
          builder: (part) => switch (part) {
            _Part.body => BodyPane(
              call: call,
              body: call.request.body,
              isRequest: true,
            ),
            _Part.headers => HeadersView(headers: call.request.headers),
            _Part.cookies => CookiesView(cookies: cookies),
          },
        );
      case _Tab.response:
        final response = call.response;
        if (response == null) {
          return Center(
            child: Text(
              call.isPending ? s.running : s.noResponseYet,
              style: context.fw.body(color: context.fw.faint),
            ),
          );
        }
        final cookies = _setCookies(response.headers);
        return _Side(
          parts: {
            _Part.body: s.tabBody,
            _Part.headers: s.tabHeaders,
            if (cookies.isNotEmpty) _Part.cookies: s.tabCookies,
          },
          value: _responsePart,
          onChanged: (v) => setState(() => _responsePart = v),
          builder: (part) => switch (part) {
            _Part.body => BodyPane(
              call: call,
              body: response.body,
              isRequest: false,
            ),
            _Part.headers => HeadersView(headers: response.headers),
            _Part.cookies => CookiesView(cookies: cookies),
          },
        );
    }
  }

  static List<FlutwireCookie> _setCookies(FlutwireHeaders headers) => [
    for (final line in headers['set-cookie']) ?parseSetCookie(line),
  ];
}

/// A row of sub-tabs above a full-height pane.
class _Side extends StatelessWidget {
  const _Side({
    required this.parts,
    required this.value,
    required this.onChanged,
    required this.builder,
  });

  final Map<_Part, String> parts;
  final _Part value;
  final ValueChanged<_Part> onChanged;
  final Widget Function(_Part) builder;

  @override
  Widget build(BuildContext context) {
    final current = parts.containsKey(value) ? value : _Part.body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedControl<_Part>(
            options: parts,
            value: current,
            onChanged: onChanged,
          ),
        ),
        Expanded(child: builder(current)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.call});

  final FlutwireCall call;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final path = call.uri.path.isEmpty ? '/' : call.uri.path;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(call: call, large: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A wrap rather than a row: on a narrow screen the sizes go to a
                // second line instead of running off the edge.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MethodChip(call.method),
                    Text(
                      formatDuration(call.duration),
                      style: t.mono(size: 12, color: t.muted),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '↑ ',
                            style: t.body(size: 12, color: t.faint),
                          ),
                          TextSpan(text: formatBytes(call.requestSize)),
                          TextSpan(
                            text: '   ↓ ',
                            style: t.body(size: 12, color: t.faint),
                          ),
                          TextSpan(text: formatBytes(call.responseSize)),
                        ],
                      ),
                      style: t.mono(size: 12, color: t.faint),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  call.graphql?.operationName ?? path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(
                    size: 14,
                    weight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (call.uri.hasQuery) ...[
                  const SizedBox(height: 3),
                  Text(
                    '?${call.uri.query}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono(size: 11.5, color: t.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
