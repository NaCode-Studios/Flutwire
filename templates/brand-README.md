<!-- docs/brand/README.md — the brand kit's own documentation. -->
# {{Name}} brand assets

{{What the mark is, in two or three sentences: the idea, then the construction, then what the idea
means for the library. A logo that cannot be explained in a sentence is decoration.}}

| File | Use |
| --- | --- |
| `{{name}}-lockup-light.svg` | the logo on a light surface |
| `{{name}}-lockup-dark.svg` | the logo on a dark surface |
| `{{name}}-lockup-mono-light.svg` / `-mono-dark.svg` | one flat ink, inherits `currentColor` |
| `{{name}}-symbol.svg` / `{{name}}-symbol-mono.svg` | the mark on its own — never as the logo |
| `{{name}}-favicon.svg` / `-light.svg` / `{{name}}-favicon-512.png` | favicon, avatar, app icon |
| `{{name}}-social-preview.png` | the GitHub social preview (2560×1280) |
| `{{name}}-tokens.css` | colour, type, space, radius and elevation tokens |
| [`../{{name}}-hero.png`](../{{name}}-hero.png) | the README banner (2560×680) |

Every SVG here is self-contained: the wordmark is outlined to paths, so it renders identically whether
or not {{Display Font}} is installed. Nothing references an external font, image or gradient.

**Construction** — {{the geometry, in numbers: the mark's box, the lockup canvas, the wordmark size
and tracking, the gap. Then clear space, expressed as a ratio of something in the logo rather than as
a pixel count, so it survives scaling.}}

**Minimum size** — {{the floor for the full-colour mark, and what to use below it.}}

**Type** — {{which face names things, which carries prose, which carries machine output. If the
library produces values a reader compares, say that they are always set in mono.}}

**Colour** — {{the accent and what it means, the neutral ramp, and the status family. Status must have
its own colours so a failing state never reads as branding.}}

**Don't** — {{the specific misuses. Be concrete: name the things someone would actually do wrong with
this mark, not generic logo advice.}}
