import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutwire/src/ui/theme/tokens.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

/// What a badge looks like: [color] as text on its own tint, over [ground].
double onTint(FlutwireTokens t, Color color, Color ground) =>
    contrast(color, Color.alphaBlend(t.tint(color), ground));

void main() {
  const minimum = 4.5;

  for (final (name, t) in [
    ('dark', FlutwireTokens.dark),
    ('light', FlutwireTokens.light),
  ]) {
    group('the $name look', () {
      test('every text colour reads on the ground and on a card', () {
        for (final text in [t.ink, t.text, t.muted, t.faint, t.copperTone]) {
          expect(contrast(text, t.ground), greaterThanOrEqualTo(minimum));
          expect(contrast(text, t.surface), greaterThanOrEqualTo(minimum));
        }
      });

      test('the status colours read as text on their own tint', () {
        for (final status in [t.ok, t.warning, t.error, t.info]) {
          expect(onTint(t, status, t.ground), greaterThanOrEqualTo(minimum));
          expect(onTint(t, status, t.surface), greaterThanOrEqualTo(minimum));
        }
      });

      test('the colours of a body read on the card they are drawn on', () {
        for (final color in [
          t.syntaxKey,
          t.syntaxString,
          t.syntaxNumber,
          t.syntaxKeyword,
          t.syntaxTag,
        ]) {
          expect(contrast(color, t.surface), greaterThanOrEqualTo(minimum));
        }
      });

      test('the text order is ink, text, muted, faint', () {
        expect(
          contrast(t.ink, t.ground),
          greaterThan(contrast(t.text, t.ground)),
        );
        expect(
          contrast(t.text, t.ground),
          greaterThan(contrast(t.muted, t.ground)),
        );
        expect(
          contrast(t.muted, t.ground),
          greaterThan(contrast(t.faint, t.ground)),
        );
      });
    });
  }

  test('text on a copper fill reads', () {
    expect(
      contrast(FlutwireTokens.onCopper, FlutwireTokens.copper),
      greaterThanOrEqualTo(minimum),
    );
  });

  test('copper never stands in for a status', () {
    for (final t in [FlutwireTokens.dark, FlutwireTokens.light]) {
      for (final status in [t.ok, t.warning, t.error, t.info]) {
        expect(status, isNot(FlutwireTokens.copper));
        expect(status, isNot(t.copperTone));
      }
    }
  });

  test('the method colours say read, write and delete', () {
    final t = FlutwireTokens.dark;
    expect(t.methodColor('GET'), t.info);
    expect(t.methodColor('post'), t.copperTone);
    expect(t.methodColor('PUT'), t.copperTone);
    expect(t.methodColor('PATCH'), t.copperTone);
    expect(t.methodColor('CALL'), t.copperTone);
    expect(t.methodColor('DELETE'), t.error);
    expect(t.methodColor('OPTIONS'), t.muted);
  });
}
