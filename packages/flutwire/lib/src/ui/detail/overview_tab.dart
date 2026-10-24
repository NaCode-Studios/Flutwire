import 'package:flutter/material.dart';

import '../../model/call.dart';
import '../../util/format.dart';
import '../actions.dart';
import '../scope.dart';

/// The facts of a call: what was asked, what came back, how long it took and
/// anything that went wrong.
class OverviewTab extends StatelessWidget {
  /// Creates the tab for [call]. [onOpenCall] opens another call of the
  /// history, which the call it repeats is.
  const OverviewTab({super.key, required this.call, this.onOpenCall});

  /// The call to describe.
  final FlutwireCall call;

  /// Opens the call with the given id.
  final ValueChanged<int>? onOpenCall;

  /// The line that names the call this one repeats, and opens it while it is
  /// still in the history.
  _Fact _repeated(BuildContext context, int from) {
    final s = context.strings;
    final original = context.session.store.find(from);
    if (original == null) return _Fact(s.resentFrom, s.resentFromGone);
    return _Fact(
      s.resentFrom,
      '${original.method}  ${original.host}${original.pathAndQuery}',
      onTap: onOpenCall == null ? null : () => onOpenCall!(from),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    final response = call.response;
    final cert = response?.certificate;
    final redirects = response?.redirects ?? const <FlutwireRedirect>[];

    final request = <_Fact>[
      if (call.resentFrom case final from?) _repeated(context, from),
      _Fact(s.url, call.uri.toString()),
      _Fact(s.method, call.method),
      _Fact(s.started, formatDateTime(call.startedAt)),
      if (call.graphql case final g?)
        _Fact(
          s.graphql,
          [
            if (g.operationType != null) g.operationType!,
            if (g.operationName != null) g.operationName!,
          ].join(' '),
        ),
      _Fact(s.requestSize, formatBytes(call.requestSize)),
      _Fact(s.source, call.source.label),
    ];

    final reply = <_Fact>[
      if (response != null)
        _Fact(
          s.status,
          [
            '${response.statusCode}',
            if (response.reasonPhrase.isNotEmpty)
              response.reasonPhrase
            else if (reasonPhraseFor(response.statusCode).isNotEmpty)
              reasonPhraseFor(response.statusCode),
          ].join(' '),
          color: t.statusColor(call),
        )
      else
        _Fact(s.status, switch (call.state) {
          FlutwireCallState.pending => s.running,
          FlutwireCallState.failed => s.failed,
          FlutwireCallState.cancelled => s.cancelled,
          FlutwireCallState.completed => s.noResponseYet,
        }, color: t.statusColor(call)),
      _Fact(
        s.duration,
        call.isPending
            ? '${formatDuration(call.duration)} …'
            : formatDuration(call.duration),
      ),
      if (call.timeToFirstByte != null)
        _Fact(s.firstByte, formatDuration(call.timeToFirstByte!)),
      if (response != null)
        _Fact(s.responseSize, formatBytes(call.responseSize)),
      if (response?.compression != null)
        _Fact(s.compression, response!.compression!),
      if (response?.remoteAddress != null)
        _Fact(
          s.remote,
          response!.remotePort == null
              ? response.remoteAddress!
              : '${response.remoteAddress}:${response.remotePort}',
        ),
      if (cert != null) _Fact(s.certificate, '${cert.subject}\n${cert.issuer}'),
      if (redirects.isNotEmpty)
        _Fact(
          s.redirects,
          redirects
              .map((r) => '${r.statusCode}  ${r.method}  ${r.location}')
              .join('\n'),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (call.error != null) ...[
          _ErrorCard(error: call.error!),
          const SizedBox(height: 14),
        ],
        _Group(title: s.tabRequest, facts: request),
        const SizedBox(height: 14),
        _Group(title: s.tabResponse, facts: reply),
      ],
    );
  }
}

class _Fact {
  const _Fact(this.label, this.value, {this.color, this.onTap});

  final String label;
  final String value;
  final Color? color;

  /// What a tap does. Without it a tap copies the value.
  final VoidCallback? onTap;
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.facts});

  final String title;
  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(title.toUpperCase(), style: t.label(color: t.faint)),
          ),
          for (var i = 0; i < facts.length; i++)
            _Row(fact: facts[i], last: i == facts.length - 1),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.fact, required this.last});

  final _Fact fact;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return InkWell(
      onTap: fact.onTap ?? () => copyText(context, fact.value),
      borderRadius: last
          ? const BorderRadius.vertical(bottom: Radius.circular(14))
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fact.label, style: t.body(size: 11.5, color: t.muted)),
            const SizedBox(height: 3),
            Text(
              fact.value,
              style: t.mono(
                size: 13,
                weight: fact.color == null ? FontWeight.w400 : FontWeight.w600,
                color: fact.color ?? t.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final FlutwireError error;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.tint(t.error),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.error.toUpperCase(),
            style: t.label(color: t.error),
          ),
          const SizedBox(height: 6),
          Text(
            error.type,
            style: t.mono(size: 13, weight: FontWeight.w600, color: t.error),
          ),
          const SizedBox(height: 4),
          SelectableText(
            error.message,
            style: t.mono(size: 12.5, color: t.ink),
          ),
        ],
      ),
    );
  }
}
