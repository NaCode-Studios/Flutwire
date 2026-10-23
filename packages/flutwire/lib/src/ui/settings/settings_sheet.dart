import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../flutwire.dart';
import '../../platform/native.dart';
import '../../version.dart';
import '../scope.dart';
import '../theme/tokens.dart';

/// Opens the settings as a sheet over the inspector.
Future<void> showSettingsSheet(BuildContext context) {
  final strings = context.strings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FlutwireScope(strings: strings, child: const _Settings()),
  );
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.settings, style: t.display(size: 22)),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: Flutwire.pausedListenable,
              builder: (context, paused, _) => _Card(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    s.recording,
                    style: t.body(
                      size: 15,
                      weight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  subtitle: Text(
                    paused ? s.paused : s.recording,
                    style: t.body(size: 12.5, color: t.muted),
                  ),
                  value: !paused,
                  onChanged: (on) => Flutwire.isPaused = !on,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _NotificationCard(),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.retentionSetting.toUpperCase(),
                    style: t.label(color: t.faint),
                  ),
                  const SizedBox(height: 6),
                  Text(switch (Flutwire.config.retention) {
                    FlutwireRetention.oneHour => s.retentionHour,
                    FlutwireRetention.oneDay => s.retentionDay,
                    FlutwireRetention.oneWeek => s.retentionWeek,
                    FlutwireRetention.forever => s.retentionForever,
                  }, style: t.display(size: 18)),
                  const SizedBox(height: 4),
                  ValueListenableBuilder(
                    valueListenable: Flutwire.calls,
                    builder: (context, calls, _) => Text(
                      s.summary(
                        calls: calls.length,
                        failed: calls.where((c) => c.isError).length,
                      ),
                      style: t.body(size: 12.5, color: t.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Flutwire $flutwireVersion  ·  NaCode Studios',
                style: t.mono(size: 11, color: t.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.ground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: child,
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    return ValueListenableBuilder<FlutwireNotificationPermission>(
      valueListenable: Flutwire.notificationPermission,
      builder: (context, permission, _) {
        final enabled = Flutwire.config.notification.enabled;
        final (text, color, button, onPressed) = switch (permission) {
          _ when !enabled => (s.notificationUnsupported, t.faint, null, null),
          FlutwireNotificationPermission.granted => (
            s.notificationOn,
            t.ok,
            null,
            null,
          ),
          FlutwireNotificationPermission.denied => (
            s.notificationDenied,
            t.warning,
            s.openSystemSettings,
            () => unawaited(Flutwire.openNotificationSettings()),
          ),
          FlutwireNotificationPermission.notDetermined => (
            s.notificationDenied,
            t.warning,
            s.allowNotifications,
            () => unawaited(Flutwire.requestNotificationPermission()),
          ),
          FlutwireNotificationPermission.unsupported => (
            s.notificationUnsupported,
            t.faint,
            null,
            null,
          ),
        };
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.notificationSetting.toUpperCase(),
                style: t.label(color: t.faint),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text, style: t.body(size: 14, color: t.ink)),
                  ),
                ],
              ),
              if (button != null) ...[
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: FlutwireTokens.indigo,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(button),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
