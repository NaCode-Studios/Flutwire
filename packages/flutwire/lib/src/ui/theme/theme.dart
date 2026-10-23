import 'package:flutter/material.dart';

import 'tokens.dart';

/// The Material theme the inspector is drawn with. It does not touch the app's
/// own theme: the inspector wraps itself in this one.
ThemeData flutwireTheme(FlutwireTokens t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: FlutwireTokens.indigo,
    onPrimary: Colors.white,
    secondary: FlutwireTokens.violet,
    onSecondary: Colors.white,
    error: t.error,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainerHighest: t.raised,
    outline: t.lineStrong,
    outlineVariant: t.line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.ground,
    canvasColor: t.surface,
    dividerColor: t.line,
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
    extensions: [t],
    textTheme: TextTheme(
      displaySmall: t.display(size: 28),
      headlineSmall: t.display(size: 22),
      titleLarge: t.display(size: 18),
      titleMedium: t.body(size: 15, weight: FontWeight.w600, color: t.ink),
      titleSmall: t.body(size: 13, weight: FontWeight.w600, color: t.ink),
      bodyLarge: t.body(size: 15),
      bodyMedium: t.body(),
      bodySmall: t.body(size: 12, color: t.muted),
      labelLarge: t.body(size: 14, weight: FontWeight.w600, color: t.ink),
      labelMedium: t.label(),
      labelSmall: t.label(size: 9.5),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.ground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t.display(size: 20),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      dragHandleColor: t.lineStrong,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: t.line),
      ),
      titleTextStyle: t.display(size: 18),
      contentTextStyle: t.body(),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.lineStrong),
      ),
      textStyle: t.body(color: t.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.raised,
      contentTextStyle: t.body(color: t.ink),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: t.lineStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.surface,
      hintStyle: t.body(color: t.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FlutwireTokens.indigo, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : t.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? FlutwireTokens.indigo
            : t.raised,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : t.lineStrong,
      ),
    ),
    iconTheme: IconThemeData(color: t.muted, size: 20),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(t.lineStrong),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(4),
    ),
  );
}
