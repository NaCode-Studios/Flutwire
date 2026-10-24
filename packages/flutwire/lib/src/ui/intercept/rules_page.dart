import 'dart:async';

import 'package:flutter/material.dart';

import '../../intercept/rule.dart';
import '../../intercept/rules.dart';
import '../../session.dart';
import '../actions.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/request_fields.dart';
import '../widgets/wire_rule.dart';
import 'rule_editor_page.dart';

/// The route that opens the rules.
Route<void> rulesRoute(FlutwireSession session) =>
    shellRoute(session, name: 'flutwire/rules', child: const RulesPage());

/// The rules that answer a request or hold it: which are in force, which are
/// off, and a way to make and change them.
///
/// Where the app did not turn mocks and breakpoints on, the page says what they
/// do and how to turn them on, because they are the one thing that changes
/// what the app sends and receives.
class RulesPage extends StatelessWidget {
  /// Creates the page.
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final session = context.session;
    final interception = session.interception;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.interceptTitle),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(WireRule.height),
          child: WireRule(),
        ),
      ),
      body: interception == null
          ? _Off(askedFor: session.config.interception)
          : _Rules(rules: interception.rules),
      bottomNavigationBar: interception == null
          ? null
          : _AddBar(rules: interception.rules),
    );
  }
}

/// What the page says where the rules are not available.
class _Off extends StatelessWidget {
  const _Off({required this.askedFor});

  /// Whether the app asked for them and cannot have them here.
  final bool askedFor;

  static const String _snippet =
      'Flutwire.init(\n  config: FlutwireConfig(interception: true),\n);';

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final t = context.fw;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.shield_outlined, size: 36, color: t.faint),
            const SizedBox(height: 14),
            Text(
              askedFor ? s.interceptUnavailableBody : s.interceptOffBody,
              textAlign: TextAlign.center,
              style: t.body(size: 14.5, color: t.ink),
            ),
            if (!askedFor) ...[
              const SizedBox(height: 18),
              Text(
                s.interceptOffHow,
                textAlign: TextAlign.center,
                style: t.body(size: 13, color: t.muted),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
                onTap: () => unawaited(copyText(context, _snippet)),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(
                      FlutwireTokens.radiusMd,
                    ),
                    border: Border.all(color: t.line),
                  ),
                  child: Text(
                    _snippet,
                    style: t.mono(size: 12.5, color: t.ink),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.rules});

  final FlutwireRules rules;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return ListenableBuilder(
      listenable: rules,
      builder: (context, _) {
        final all = rules.all;
        if (all.isEmpty) {
          return EmptyState(
            title: s.interceptEmptyTitle,
            message: s.interceptEmptyBody,
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _RuleTile(rule: all[index], rules: rules),
            ),
          ),
        );
      },
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.rules});

  final FlutwireRule rule;
  final FlutwireRules rules;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final isMock = rule.kind == FlutwireRuleKind.mock;
    final tone = isMock ? t.copperTone : t.info;
    final detail = [
      isMock ? s.interceptMock : s.interceptBreakpoint,
      if (isMock) '${rule.response!.statusCode}',
      if (rule.name.isNotEmpty) '${rule.method ?? 'ANY'} ${rule.pattern}',
    ].join('  ·  ');
    return Opacity(
      opacity: rule.enabled ? 1 : 0.55,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          onTap: () => unawaited(
            Navigator.of(context).push(
              ruleEditorRoute(context.session, kind: rule.kind, rule: rule),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
              border: Border.all(color: t.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.tint(tone),
                    borderRadius: BorderRadius.circular(
                      FlutwireTokens.radiusSm,
                    ),
                  ),
                  child: Icon(
                    isMock
                        ? Icons.auto_fix_high_rounded
                        : Icons.pause_circle_outline_rounded,
                    size: 20,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The path is what tells two rules for one host apart, so
                      // the address wraps over three lines before it is cut,
                      // and stays with its method on the first.
                      Text(
                        rule.name.isEmpty
                            ? rule.label.replaceFirst(' ', '\u00a0')
                            : rule.label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: t.mono(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body(size: 11.5, color: t.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: rule.enabled,
                  onChanged: (value) =>
                      rules.setEnabled(rule.id, enabled: value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two buttons that make a rule from nothing.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.rules});

  final FlutwireRules rules;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    void add(FlutwireRuleKind kind) => unawaited(
      Navigator.of(context).push(ruleEditorRoute(context.session, kind: kind)),
    );
    return EditorBottomBar(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => add(FlutwireRuleKind.mock),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(s.interceptNewMock),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => add(FlutwireRuleKind.breakpoint),
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
              label: Text(s.interceptNewBreakpoint),
            ),
          ),
        ],
      ),
    );
  }
}
