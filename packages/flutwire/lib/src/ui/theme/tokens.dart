import 'package:flutter/material.dart';

import '../../model/call.dart';

/// The colours, type and shapes of the inspector.
///
/// They follow the NaCode Studios identity: ink surfaces on dark and a quiet
/// wash on light, the indigo to violet to pink gradient used once per surface
/// and never under text, and a status family of its own so that a failing call
/// never reads as branding.
@immutable
final class FlutwireTokens extends ThemeExtension<FlutwireTokens> {
  /// Creates a set of tokens. Most code uses [dark] or [light].
  const FlutwireTokens({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.raised,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.text,
    required this.muted,
    required this.faint,
    required this.ok,
    required this.warning,
    required this.error,
    required this.info,
    required this.syntaxKey,
    required this.syntaxString,
    required this.syntaxNumber,
    required this.syntaxKeyword,
    required this.syntaxPunctuation,
    required this.syntaxTag,
    required this.match,
    required this.currentMatch,
  });

  /// The dark look, which is the identity's home.
  static const FlutwireTokens dark = FlutwireTokens(
    brightness: Brightness.dark,
    ground: Color(0xFF07070E),
    surface: Color(0xFF0D0D16),
    raised: Color(0xFF181832),
    line: Color(0xFF1E1E3A),
    lineStrong: Color(0xFF2C2C52),
    ink: Color(0xFFF4F3FA),
    text: Color(0xFFD2D0E6),
    muted: Color(0xFFA9A6C4),
    faint: Color(0xFF77748F),
    ok: Color(0xFF2DD4A0),
    warning: Color(0xFFF5B544),
    error: Color(0xFFF0524F),
    info: Color(0xFF5BA8F5),
    syntaxKey: Color(0xFFA5A8FF),
    syntaxString: Color(0xFFE9C7A0),
    syntaxNumber: Color(0xFFF2A1C9),
    syntaxKeyword: Color(0xFFC4A9FF),
    syntaxPunctuation: Color(0xFF77748F),
    syntaxTag: Color(0xFF8FB8FF),
    match: Color(0x66F5B544),
    currentMatch: Color(0xFFF5B544),
  );

  /// The light look.
  static const FlutwireTokens light = FlutwireTokens(
    brightness: Brightness.light,
    ground: Color(0xFFF7F6FB),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    line: Color(0xFFE4E3EC),
    lineStrong: Color(0xFFD3D1E0),
    ink: Color(0xFF12121A),
    text: Color(0xFF2A2740),
    muted: Color(0xFF6B6A80),
    faint: Color(0xFF9C99AE),
    ok: Color(0xFF0E9F74),
    warning: Color(0xFFB7791F),
    error: Color(0xFFD63A37),
    info: Color(0xFF2F7FD0),
    syntaxKey: Color(0xFF4F46E5),
    syntaxString: Color(0xFF9A5B13),
    syntaxNumber: Color(0xFFBE185D),
    syntaxKeyword: Color(0xFF7C3AED),
    syntaxPunctuation: Color(0xFF9C99AE),
    syntaxTag: Color(0xFF1D5FBF),
    match: Color(0x55F5B544),
    currentMatch: Color(0xFFF5B544),
  );

  /// The brand indigo.
  static const Color indigo = Color(0xFF6366F1);

  /// The brand violet.
  static const Color violet = Color(0xFF8B5CF6);

  /// The brand pink.
  static const Color pink = Color(0xFFEC4899);

  /// The brand gradient. It appears once on a surface, as a rule, a small mark
  /// or a progress bar, and never behind text.
  static const LinearGradient gradient = LinearGradient(
    colors: [indigo, violet, pink],
  );

  /// Whether this is the dark look.
  final Brightness brightness;

  /// The page behind everything.
  final Color ground;

  /// A card or a sheet.
  final Color surface;

  /// Something that sits on a card, such as a selected row or a field.
  final Color raised;

  /// A hairline between things.
  final Color line;

  /// A border that has to be seen.
  final Color lineStrong;

  /// Headings and the text that matters.
  final Color ink;

  /// Running text.
  final Color text;

  /// Secondary text.
  final Color muted;

  /// Hints, units and disabled text.
  final Color faint;

  /// A successful call.
  final Color ok;

  /// A client error, or a slow call.
  final Color warning;

  /// A failure or a server error.
  final Color error;

  /// A redirect, or information.
  final Color info;

  /// A JSON key or an XML attribute name.
  final Color syntaxKey;

  /// A string literal.
  final Color syntaxString;

  /// A number.
  final Color syntaxNumber;

  /// `true`, `false` and `null`.
  final Color syntaxKeyword;

  /// Braces, commas and colons.
  final Color syntaxPunctuation;

  /// An XML or HTML tag name.
  final Color syntaxTag;

  /// The background of a search match.
  final Color match;

  /// The background of the match the search is on.
  final Color currentMatch;

  /// Whether this is the dark look.
  bool get isDark => brightness == Brightness.dark;

  /// The colour that stands for how [call] went.
  Color statusColor(FlutwireCall call) {
    switch (call.state) {
      case FlutwireCallState.pending:
        return violetTone;
      case FlutwireCallState.failed:
        return error;
      case FlutwireCallState.cancelled:
        return faint;
      case FlutwireCallState.completed:
        return colorForStatus(call.statusCode);
    }
  }

  /// The colour for an HTTP [statusCode].
  Color colorForStatus(int? statusCode) => switch (FlutwireStatusClass.of(
    statusCode,
  )) {
    FlutwireStatusClass.success => ok,
    FlutwireStatusClass.redirect || FlutwireStatusClass.informational => info,
    FlutwireStatusClass.clientError => warning,
    FlutwireStatusClass.serverError => error,
    FlutwireStatusClass.none => faint,
  };

  /// The violet of a call that is still running, readable on this look.
  Color get violetTone => isDark ? const Color(0xFFA78BFA) : violet;

  /// The colour of the tag for an HTTP [method].
  Color methodColor(String method) => switch (method.toUpperCase()) {
    'GET' => info,
    'POST' => violetTone,
    'PUT' || 'PATCH' => warning,
    'DELETE' => error,
    _ => muted,
  };

  /// A [color] at a strength that works as the fill behind its own text.
  Color tint(Color color) => color.withValues(alpha: isDark ? 0.16 : 0.12);

  /// Headlines: Bricolage Grotesque, semibold.
  TextStyle display({double size = 22, Color? color}) => TextStyle(
    fontFamily: 'FlutwireDisplay',
    package: 'flutwire',
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: 1.15,
    letterSpacing: -size * 0.02,
    color: color ?? ink,
  );

  /// The one accented word of a headline: Instrument Serif, italic.
  TextStyle accent({double size = 22, Color? color}) => TextStyle(
    fontFamily: 'FlutwireSerif',
    package: 'flutwire',
    fontStyle: FontStyle.italic,
    fontSize: size * 1.08,
    height: 1.1,
    color: color ?? ink,
  );

  /// Running text: Inter.
  TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: 'FlutwireText',
    package: 'flutwire',
    fontWeight: weight,
    fontSize: size,
    height: 1.4,
    color: color ?? text,
  );

  /// Anything a machine produced: JetBrains Mono.
  TextStyle mono({
    double size = 12.5,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.45,
  }) => TextStyle(
    fontFamily: 'FlutwireMono',
    package: 'flutwire',
    fontWeight: weight,
    fontSize: size,
    height: height,
    color: color ?? text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A small label in capitals with wide tracking, set in the mono face.
  TextStyle label({double size = 10.5, Color? color}) => TextStyle(
    fontFamily: 'FlutwireMono',
    package: 'flutwire',
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: 1.2,
    letterSpacing: size * 0.14,
    color: color ?? muted,
  );

  @override
  FlutwireTokens copyWith({Brightness? brightness}) =>
      brightness == Brightness.light
      ? light
      : brightness == Brightness.dark
      ? dark
      : this;

  @override
  FlutwireTokens lerp(ThemeExtension<FlutwireTokens>? other, double t) =>
      t < 0.5 || other is! FlutwireTokens ? this : other;

  /// The tokens in force below [context].
  static FlutwireTokens of(BuildContext context) =>
      Theme.of(context).extension<FlutwireTokens>() ?? dark;
}
