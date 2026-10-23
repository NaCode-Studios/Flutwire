import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scope.dart';
import '../theme/tokens.dart';

/// The font size, before text scaling, that every monospaced view is set in.
const double bodyFontSize = 12.5;

/// The height of one row of code, before text scaling.
///
/// It is a whole number of logical pixels on purpose: rows have a fixed height
/// so that finding the row of a search match is a multiplication, and a
/// fractional height would let that arithmetic drift over thousands of rows.
const double bodyLineHeight = 18;

/// The most characters one row shows. A longer line is cut into several rows,
/// because a minified body can be a single line of hundreds of thousands of
/// characters and one text object that long would stall layout.
const int bodyMaxRowChars = 2000;

/// The width below which the inspector uses its phone layout.
const double bodyNarrowWidth = 600;

/// How many characters of a value the fields and parts views show before they
/// offer "show more".
const int bodyPreviewChars = 400;

/// The most characters of one value those views will ever lay out as a single
/// text, even when the user asks for all of it. Search covers the same range,
/// so that every match can be drawn.
const int bodyTextLimit = 20000;

/// The measures that every monospaced view of the body viewer shares.
@immutable
final class BodyMetrics {
  const BodyMetrics._({
    required this.fontSize,
    required this.lineHeight,
    required this.charWidth,
    required this.style,
    required this.strut,
  });

  /// Measures the monospaced face at the size the user's text scale asks for.
  ///
  /// The scale is applied here, once, rather than by each [Text], so that the
  /// row height and the character width the views do arithmetic with are the
  /// ones that are drawn.
  factory BodyMetrics.resolve(FlutwireTokens tokens, TextScaler scaler) {
    final fontSize = math.min(
      math.max(scaler.scale(bodyFontSize), bodyFontSize * 0.9),
      bodyFontSize * 2,
    );
    final lineHeight = (bodyLineHeight * fontSize / bodyFontSize)
        .roundToDouble();
    // Nothing may be inherited. The Material text style that sits above this
    // one carries a letter spacing, and a quarter of a pixel on every cell
    // makes a row of fifty characters overflow its width by a whole one. The
    // row arithmetic holds only if the cell that is drawn is the one that was
    // measured.
    final style = tokens
        .mono(size: fontSize, height: lineHeight / fontSize)
        .copyWith(
          inherit: false,
          leadingDistribution: TextLeadingDistribution.even,
          // The inspector shows the characters that were sent. A ligature
          // would draw `-->` or `!=` as something else.
          fontFeatures: const [
            FontFeature.tabularFigures(),
            FontFeature.disable('calt'),
            FontFeature.disable('liga'),
          ],
        );
    return BodyMetrics._(
      fontSize: fontSize,
      lineHeight: lineHeight,
      charWidth: _measureCell(style),
      style: style,
      strut: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    );
  }

  /// The size of the text in logical pixels.
  final double fontSize;

  /// The height of a row in logical pixels.
  final double lineHeight;

  /// The advance of one character of the monospaced face.
  final double charWidth;

  /// The style of code: the mono face with the row height built in.
  final TextStyle style;

  /// A strut that makes every line exactly [lineHeight] tall, whatever glyphs
  /// it holds.
  final StrutStyle strut;

  /// How many whole characters fit in [width].
  int cellsIn(double width) => math.max(1, (width / charWidth).floor());
}

double _measureCell(TextStyle style) {
  const sample = 32;
  final painter = TextPainter(
    text: TextSpan(text: '0' * sample, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout();
  final width = painter.width / sample;
  painter.dispose();
  return width;
}

/// Keeps a [BodyMetrics] up to date for a [State].
///
/// The face is measured, not assumed, because the width of a cell is whatever
/// the font on the device gives, and the measure has to be taken again when
/// the text scale changes or when a font finishes loading after the first
/// frame.
mixin BodyMetricsState<T extends StatefulWidget> on State<T> {
  FlutwireTokens? _tokens;
  TextScaler? _scaler;

  /// The metrics in force.
  late BodyMetrics metrics;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = context.fw;
    final scaler = MediaQuery.textScalerOf(context);
    if (!identical(tokens, _tokens) || scaler != _scaler) {
      _tokens = tokens;
      _scaler = scaler;
      metrics = BodyMetrics.resolve(tokens, scaler);
    }
  }

  void _fontsChanged() {
    if (!mounted) return;
    setState(() => metrics = BodyMetrics.resolve(context.fw, _scaler!));
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    super.dispose();
  }
}
