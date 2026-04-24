---
name: expense-tracker-design
description: Use this skill to generate well-branded interfaces and assets for the Expense Tracker product (a Splitwise-inspired expense & balance app, Flutter + Go), either for production or throwaway prototypes/mocks.
user-invocable: true
---

Read the `README.md` file within this skill, and explore the other available files.

This skill contains:
- `README.md` — brand voice, visual foundations, iconography
- `colors_and_type.css` — CSS custom properties (colors, type, spacing, radii, breakpoints)
- `preview/` — visual specimen cards (colors, type, spacing, components)
- `ui_kits/mobile/` — React recreation of the Flutter mobile app (Android + iOS frames, all screens, components)
- `../frontend/` — imported Flutter source code for direct reference

If creating visual artifacts (slides, mocks, throwaway prototypes, etc), link `ui/colors_and_type.css`, use its vars (`--accent`, `--positive`, `--fg1`, etc), and copy components from `ui/ui_kits/mobile/Components.jsx` as needed. Icons: substitute Lucide from CDN (closest match to Material/Cupertino outlined style).

If working on production code, read the Flutter source under `frontend/lib/` — it's the canonical source. Respect the theme family system (`ThemePackCatalog`), the three theme variants, and the platform adaptive shell (Material on Android/Web, Cupertino on iOS).

If the user invokes this skill without any other guidance, ask them what they want to build or design, ask questions about the target platform (mobile vs desktop vs web), and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

Key rules:
- Currency defaults to **INR** (`₹`).
- Positive balances use `#1B8C67`; negative uses `colorScheme.error` / `#BA1A1A`.
- Sentence-case copy always — no title case, no ALL CAPS, no emoji.
- Cards are flat (elevation 0, 14px radius, hairline border). FAB is the only elevated surface.
- Default theme family is **Splitwise** (green `#26A17B`).
