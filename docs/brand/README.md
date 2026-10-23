# Flutwire brand kit

Everything here belongs to Flutwire alone. The look is the product's own: it does not borrow the palette, the type or the shapes of the studio that builds it.

## The mark

The mark is a wire bent into an f that ends in a live node. The wire is the line a call travels on, and the node is the call itself. The node is the one copper thing in the drawing. The stroke is 40 units everywhere, the same as the stem of the letters in the wordmark, so the mark and the name read as a single drawing.

| File | Use it for |
| --- | --- |
| `flutwire-lockup-light.svg` | The mark and the name on a light ground |
| `flutwire-lockup-dark.svg` | The mark and the name on a dark ground |
| `flutwire-lockup-mono-light.svg`, `flutwire-lockup-mono-dark.svg` | One flat ink, taken from the surrounding text colour with `currentColor`. The two files are identical on purpose |
| `flutwire-symbol.svg`, `flutwire-symbol-dark.svg` | The mark alone, on a light and on a dark ground |
| `flutwire-symbol-mono.svg` | The mark alone in one flat ink |
| `flutwire-favicon.svg`, `flutwire-favicon-light.svg` | The mark on a rounded tile, for a favicon or an avatar |
| `flutwire-favicon-512.png` | The same tile as a 512 pixel image |
| `flutwire-social-preview.png` | The 2560 by 1280 image for the repository's social preview |
| `flutwire-tokens.css` | Colour, type, shape and space as custom properties |
| `../flutwire-hero.png` | The 2560 by 680 banner at the top of the README |

Every SVG is self-contained. The name is drawn as outlines, so it looks the same whether or not DM Sans is installed, and nothing refers to a font, an image or a gradient.

## Construction

The symbol sits in a box 292 units wide and 366 tall. The stem is a 40 unit stroke with round ends, its centre line 108 units from the left edge. At the top it turns through a quarter circle of radius 84 and runs on to a rounded end. The crossbar is a 40 unit stroke whose centre line is 136 units from the top, from 20 units in from the left edge to the node. The node is a circle of radius 36 centred at the end of the crossbar, which makes it 1.8 times as wide as the stroke.

The lockup canvas is 1408 by 366 and tight to its content. The name is set in DM Sans semibold at 310 units to the em, at its largest optical size, with the letter spacing pulled in by 6 thousandths of an em. Its baseline is the bottom edge of the stem, and it starts 84 units to the right of the node.

Clear space is the width of the node, 72 units, on every side. That is a little under a fifth of the height of the mark, so it scales with it.

## Minimum size

The symbol is not drawn below 14 pixels tall, and the lockup not below 28 pixels tall. Smaller than that, use the favicon tile on its own, because at 14 pixels the node still reads as a dot but the name does not read as letters.

## Type

DM Sans names things and explains them. It is used at its display optical size, semibold with the letters pulled in by 2 percent, for headlines, and at its text size for prose. DM Mono carries everything a machine produced, every number, and the small capital labels that sit above a value, set with 14 percent of letter spacing. DM Sans has no tabular figures, which is the reason numbers are set in the mono face: a column of durations and sizes has to line up.

Both faces are bundled with the package, cut down to the Latin range, under the SIL Open Font License. The licence is in `packages/flutwire/fonts`.

## Colour

Copper, `#f0803a`, is the colour of the node and the only brand colour. A filled control is copper with `#1a0f08` text on it. Copper as text or as a border uses a tone that reads on the look in force: copper itself on dark, `#b4531a` on light.

The neutrals are warm. The dark look is graphite, from `#0e0f11` for the ground to `#f4f3ef` for the ink. The light look is paper, `#f6f5f1` for the ground and `#17181b` for the ink.

Status is a family of its own and never borrows from copper, so a failing call does not read as branding. On the dark look success is `#3dd6a0`, a client error or a slow call `#f2c94c`, a failure `#f25c6b` and information `#5aa9ff`. On the light look they are `#097051`, `#825e00`, `#b92b3a` and `#2265ac`. Every text colour, every status colour on its own tint and every colour of a body reaches 4.5 to 1 against the surface it is drawn on, in both looks, and a test in the package keeps it that way.

Reads are blue, writes are copper and a delete is red, so the method tag says what a call does before the call is opened.

## Don't

- Do not recolour the node or the wire. Copper is always copper, and the wire is always the ink of the look. The only exception is the mono files.
- Do not put the dark-ink symbol on a dark ground, or the light-ink one on a light ground. Pick the file for the ground.
- Do not set the name in live text or in another typeface. Use the outlined SVG.
- Do not thin or thicken the stroke, move the node off the end of the crossbar, or break the crossbar from the stem.
- Do not add a shadow, a glow, a gradient or an outline to the mark.
- Do not use copper for a status, and do not use a status colour for the brand.
- Do not stretch, tilt or crop the mark, and do not place it on a busy photograph.
