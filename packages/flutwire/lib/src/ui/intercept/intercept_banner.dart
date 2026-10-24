import 'dart:async';

import 'package:flutter/material.dart';

import '../../intercept/interception.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';
import 'held.dart';
import 'rules_page.dart';

/// The lines above the list that say Flutwire is changing traffic: how many
/// rules are in force, and which requests are held, with a way to look at
/// them. It is not there while no rule is in force and nothing is held.
class InterceptBanner extends StatelessWidget {
  /// Creates the banner.
  const InterceptBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final interception = context.session.interception;
    if (interception == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([
        interception.rules,
        interception.breakpoints,
      ]),
      builder: (context, _) => _lines(context, interception),
    );
  }

  Widget _lines(BuildContext context, FlutwireInterception interception) {
    final s = context.strings;
    final t = context.fw;
    final session = context.session;
    final held = interception.breakpoints.held;
    final active = interception.rules.activeCount;
    if (held.isEmpty && active == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          if (held.isNotEmpty)
            _Line(
              icon: Icons.pause_circle_outline_rounded,
              tone: t.warning,
              text: s.heldBanner(held.length),
              action: s.heldReview,
              onTap: () {
                final oldest = held.first;
                interception.breakpoints.claim(oldest.id);
                unawaited(
                  Navigator.of(context).push(heldRoute(session, oldest)),
                );
              },
            ),
          if (active > 0)
            _Line(
              icon: Icons.auto_fix_high_rounded,
              tone: t.copperTone,
              text: s.interceptRulesActive(active),
              onTap: () => unawaited(
                Navigator.of(context).push(
                  shellRoute(
                    session,
                    name: 'flutwire/rules',
                    child: const RulesPage(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.tone,
    required this.text,
    required this.onTap,
    this.action,
  });

  final IconData icon;
  final Color tone;
  final String text;
  final String? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: t.tint(tone),
        borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FlutwireTokens.radiusMd),
              border: Border.all(color: tone.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: tone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: t.body(
                      size: 13,
                      weight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                if (action != null)
                  Text(
                    action!,
                    style: t.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: tone,
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, size: 18, color: tone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
