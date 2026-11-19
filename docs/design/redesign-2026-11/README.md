# Redesign 2026-11: design package

The owner's design package for M9 (D22 in [[01 Brainstorm]], ADR-23 in [[02 Architecture]]). It is a visual reference, not a contract: where it disagrees with the app, D22 and the code win.

| Path | What |
|---|---|
| `SPEC.md` | The owner's specification (Ukrainian): type scale, colours, icons, components, screens |
| `CARD_SPEC.md` | The owner's task card v2, the "quiet card" (Ukrainian, 2026-11-17, M11 T-1103): replaces the TaskCard section of `SPEC.md`; the notes block and the editor order and hints added 2026-11-20 (0.8.1) |
| `mockups/*.dc.html` | Source of the mockups: sizes, colours, texts, states. They need the design tool's `support.js` and React to open, which are not kept; read them as text. `*Dark.dc.html` only switch the main file to dark |
| `screens/*.png` | The mockups of Today, Plan and Tasks in light and dark, 2× |

## What is current
- **Task card:** `CARD_SPEC.md` (v2 + notes block). The "TaskCard" section of `SPEC.md` is superseded. The reference code in both files was never compiled; the real code is `lib/shared/task_card.dart`.
- **Task editor:** the field order and hint style at the end of `CARD_SPEC.md`.
- **Colours and sizes:** `lib/app/app_colors.dart` (`AppColors`, `AppDims`). Priority colours are the app's own (D1), not the package's five fixed ones.
- **Screens, header, navigation, FAB:** `SPEC.md` and the mockups, with the deviations listed in D22 (no due times, Today's progress counts today's list, no tap on a free slot to add, no bundled font).
- Read the package only for UI work on these screens; it is not needed for planner or data work.

Not kept: the package's token file (now `lib/app/app_colors.dart`) and its reference widgets (never compiled; `flutter analyze` would read them).
