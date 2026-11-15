# Redesign 2026-11: design package

The owner's design package for M9 (D22 in [[01 Brainstorm]], ADR-23 in [[02 Architecture]]). It is a visual reference, not a contract: where it disagrees with the app, D22 and the code win.

| Path | What |
|---|---|
| `SPEC.md` | The owner's specification (Ukrainian): type scale, colours, icons, components, screens |
| `mockups/*.dc.html` | Source of the mockups: sizes, colours, texts, states. They need the design tool's `support.js` and React to open, which are not kept; read them as text. `*Dark.dc.html` only switch the main file to dark |
| `screens/*.png` | The mockups of Today, Plan and Tasks in light and dark, 2× |

Not kept: the package's token file (now `lib/app/app_colors.dart`) and its reference widgets (never compiled; `flutter analyze` would read them).
