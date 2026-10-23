import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/lookup.dart';
import '../session.dart';
import 'scope.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';

/// Dresses everything below it as the inspector: the Flutwire theme, the
/// strings of the right language, the [session] to work on, and the
/// localisations Material widgets need even when the app around them has none,
/// such as a `CupertinoApp`.
class FlutwireShell extends StatelessWidget {
  /// Wraps [child]. Leave [systemUi] on for a screen of its own, and turn it
  /// off for something that sits above the app, which must not restyle the
  /// status bar.
  const FlutwireShell({
    super.key,
    required this.session,
    required this.child,
    this.systemUi = true,
  });

  /// What the screens below work on.
  final FlutwireSession session;

  /// The screen to dress.
  final Widget child;

  /// Whether to set the style of the status bar and the navigation bar.
  final bool systemUi;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: session.themeMode,
      builder: (context, mode, _) => _dress(context, mode),
    );
  }

  Widget _dress(BuildContext context, ThemeMode mode) {
    final platform = MediaQuery.platformBrightnessOf(context);
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platform == Brightness.dark,
    };
    final tokens = dark ? FlutwireTokens.dark : FlutwireTokens.light;
    final locale =
        session.config.locale ?? Localizations.maybeLocaleOf(context);
    Widget dressed = Theme(
      data: flutwireTheme(tokens),
      child: FlutwireScope(
        session: session,
        strings: stringsFor(locale),
        child: child,
      ),
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
    if (!systemUi) return dressed;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: dressed,
    );
  }
}

/// A route that shows [child] dressed as the inspector, working on [session].
///
/// Dressing happens per route because the Navigator is the app's, not
/// Flutwire's: a route pushed onto it starts outside the theme and the scope.
Route<void> shellRoute(
  FlutwireSession session, {
  required String name,
  required Widget child,
}) => MaterialPageRoute<void>(
  settings: RouteSettings(name: name),
  builder: (_) => FlutwireShell(session: session, child: child),
);
