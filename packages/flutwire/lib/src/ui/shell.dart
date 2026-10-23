import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../flutwire.dart';
import '../l10n/strings.dart';
import 'scope.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

/// Dresses everything below it as the inspector: the Flutwire theme, the
/// strings of the right language, and the localisations Material widgets need
/// even when the app around them has none, such as a `CupertinoApp`.
class FlutwireShell extends StatelessWidget {
  /// Wraps [child].
  const FlutwireShell({super.key, required this.child});

  /// The screen to dress.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Flutwire.themeModeListenable,
      builder: (context, mode, _) => _dress(context, mode),
    );
  }

  Widget _dress(BuildContext context, ThemeMode mode) {
    final config = Flutwire.config;
    final platform = MediaQuery.platformBrightnessOf(context);
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platform == Brightness.dark,
    };
    final tokens = dark ? FlutwireTokens.dark : FlutwireTokens.light;
    final locale = config.locale ?? Localizations.maybeLocaleOf(context);
    Widget dressed = Theme(
      data: flutwireTheme(tokens),
      child: FlutwireScope(strings: FlutwireStrings.of(locale), child: child),
    );
    final hasMaterial =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null;
    if (!hasMaterial) {
      dressed = Localizations(
        locale: locale ?? const Locale('en'),
        delegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: dressed,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: dressed,
    );
  }
}
