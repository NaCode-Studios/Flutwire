import 'package:flutter/material.dart';

import '../../model/call.dart';

/// The colours, type and shapes of the inspector.
///
/// Flutwire looks like a wire at work: warm graphite on dark and warm paper on
/// light, one accent, copper, which is the colour of the node at the end of the
/// logo's wire, and a status family of its own so that a failing call never
/// reads as branding. Corners are tight, rules are hairlines, and every number
/// is set in the mono face so that columns of them line up.
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

  /// The dark look: graphite with warm whites.
  static const FlutwireTokens dark = FlutwireTokens(
    brightness: Brightness.dark,
    ground: Color(0xFF0E0F11),
    surface: Color(0xFF141518),
    raised: Color(0xFF1B1D21),
    line: Color(0xFF25272C),
    lineStrong: Color(0xFF343740),
    ink: Color(0xFFF4F3EF),
    text: Color(0xFFCFCDC6),
    muted: Color(0xFF9C9A93),
    faint: Color(0xFF82807B),
    ok: Color(0xFF3DD6A0),
    warning: Color(0xFFF2C94C),
    error: Color(0xFFF25C6B),
    info: Color(0xFF5AA9FF),
    syntaxKey: Color(0xFFF4A06A),
    syntaxString: Color(0xFFE9D8A6),
    syntaxNumber: Color(0xFF7FD6E4),
    syntaxKeyword: Color(0xFFF29AAE),
    syntaxPunctuation: Color(0xFF6D6C67),
    syntaxTag: Color(0xFF8FB8FF),
    match: Color(0x66F2C94C),
    currentMatch: Color(0xFFF2C94C),
  );

  /// The light look: warm paper with ink.
  static const FlutwireTokens light = FlutwireTokens(
    brightness: Brightness.light,
    ground: Color(0xFFF6F5F1),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    line: Color(0xFFE4E2DB),
    lineStrong: Color(0xFFD2CFC6),
    ink: Color(0xFF17181B),
    text: Color(0xFF33343A),
    muted: Color(0xFF55565D),
    faint: Color(0xFF6D6E73),
    ok: Color(0xFF097051),
    warning: Color(0xFF825E00),
    error: Color(0xFFB92B3A),
    info: Color(0xFF2265AC),
    syntaxKey: Color(0xFFB4531A),
    syntaxString: Color(0xFF7A5A12),
    syntaxNumber: Color(0xFF0B7285),
    syntaxKeyword: Color(0xFFB3304A),
    syntaxPunctuation: Color(0xFF9A9A9F),
    syntaxTag: Color(0xFF1D5FBF),
    match: Color(0x55F2C94C),
    currentMatch: Color(0xFFF2C94C),
  );

  /// Copper, the one brand colour. It fills the node of the logo and every
  /// filled control. Text on it is [onCopper].
  static const Color copper = Color(0xFFF0803A);

  /// Text and icons on a [copper] fill.
  static const Color onCopper = Color(0xFF1A0F08);

  /// The radius of tags and small marks.
  static const double radiusXs = 5;

  /// The radius of chips and badges.
  static const double radiusSm = 8;

  /// The radius of fields, buttons and rows.
  static const double radiusMd = 12;

  /// The radius of cards.
  static const double radiusLg = 14;

  /// The radius of the top corners of a sheet.
  static const double radiusXl = 20;

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

  /// Copper as text, borders and icons, readable on this look.
  Color get copperTone => isDark ? copper : const Color(0xFFB4531A);

  /// The colour that stands for how [call] went.
  Color statusColor(FlutwireCall call) {
    switch (call.state) {
      case FlutwireCallState.pending:
        return copperTone;
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

  /// The colour of the tag for an HTTP [method]: reads are blue, writes are
  /// copper, a delete is red.
  Color methodColor(String method) => switch (method.toUpperCase()) {
    'GET' || 'HEAD' => info,
    'POST' || 'PUT' || 'PATCH' || 'CALL' => copperTone,
    'DELETE' => error,
    _ => muted,
  };

  /// A [color] at a strength that works as the fill behind its own text.
  Color tint(Color color) => color.withValues(alpha: isDark ? 0.16 : 0.12);

  /// Headlines: DM Sans at its display optical size, semibold.
  TextStyle display({double size = 22, Color? color}) => TextStyle(
    fontFamily: 'FlutwireDisplay',
    package: 'flutwire',
    fontWeight: FontWeight.w600,
    fontSize: size,
    height: 1.15,
    letterSpacing: -size * 0.02,
    color: color ?? ink,
  );

  /// Running text: DM Sans.
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

  /// Anything a machine produced, and every number: DM Mono.
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
