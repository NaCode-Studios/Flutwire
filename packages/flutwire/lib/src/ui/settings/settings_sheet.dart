import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../platform/native.dart';
import '../../version.dart';
import '../scope.dart';
import '../shell.dart';
import '../theme/tokens.dart';

/// Opens the settings as a sheet over the inspector.
Future<void> showSettingsSheet(BuildContext context) {
  final session = context.session;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // The sheet dresses itself instead of keeping the theme it was opened
    // under, so it repaints at once when the look is changed from inside it.
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    builder: (_) => FlutwireShell(session: session, child: const _Settings()),
  );
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return Material(
      color: t.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FlutwireTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
              Text(s.settings, style: t.display(size: 22)),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: session.paused,
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
                    onChanged: (on) => session.setPaused(!on),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const _NotificationCard(),
              const SizedBox(height: 12),
              const _AppearanceCard(),
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
                    Text(switch (session.config.retention) {
                      FlutwireRetention.oneHour => s.retentionHour,
                      FlutwireRetention.oneDay => s.retentionDay,
                      FlutwireRetention.oneWeek => s.retentionWeek,
                      FlutwireRetention.forever => s.retentionForever,
                    }, style: t.display(size: 18)),
                    const SizedBox(height: 4),
                    ValueListenableBuilder(
                      valueListenable: session.store.calls,
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
      ),
    );
  }
}

/// Picks the look: the device's, light or dark. The pick is applied at once
/// and remembered.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    final options = [
      (ThemeMode.system, Icons.brightness_auto_rounded, s.themeSystem),
      (ThemeMode.light, Icons.light_mode_rounded, s.themeLight),
      (ThemeMode.dark, Icons.dark_mode_rounded, s.themeDark),
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.appearanceSetting.toUpperCase(),
            style: t.label(color: t.faint),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: session.themeMode,
            builder: (context, mode, _) => Row(
              children: [
                for (final (index, (value, icon, label))
                    in options.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ThemeOption(
                      icon: icon,
                      label: label,
                      selected: mode == value,
                      onTap: () => session.setThemeMode(value),
                    ),
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final tone = t.copperTone;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? tone.withValues(alpha: 0.55) : t.lineStrong,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: selected ? tone : t.muted),
              const SizedBox(height: 4),
              Text(
                label,
                style: t.body(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: selected ? tone : t.muted,
                ),
              ),
            ],
          ),
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
    // A Material rather than a decorated box, so a tile inside it paints its
    // ripple on the card instead of under it.
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: t.ground,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlutwireTokens.radiusLg),
          side: BorderSide(color: t.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard();

  @override
  Widget build(BuildContext context) {
    final t = context.fw;
    final s = context.strings;
    final session = context.session;
    return ValueListenableBuilder<FlutwireNotificationPermission>(
      valueListenable: session.notificationPermission,
      builder: (context, permission, _) {
        final enabled = session.config.notification.enabled;
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
            () => unawaited(session.openNotificationSettings()),
          ),
          FlutwireNotificationPermission.notDetermined => (
            s.notificationDenied,
            t.warning,
            s.allowNotifications,
            () => unawaited(session.requestNotificationPermission()),
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
                FilledButton(onPressed: onPressed, child: Text(button)),
              ],
            ],
          ),
        );
      },
    );
  }
}
