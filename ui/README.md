# Expense Tracker — Design System

A design system extracted from the **expense_tracker** codebase: a Splitwise-inspired expense and balance tracker built with Flutter (iOS / Android / Web) and a Python/FastAPI + MongoDB backend.

## Source & references

All source truth lives in the attached repo: **Blazkowiz47/expense_tracker** (`master`).

- Flutter app code: `frontend/lib/` (imported here under the same path for reference)
- Theme + color definitions: `frontend/lib/core/theme/app_theme.dart`, `frontend/lib/core/theme/theme_pack.dart`
- Spacing + breakpoints: `frontend/lib/core/constants/`
- Screens: `frontend/lib/features/{friends,groups,activity,account,expenses,theme}/view/`
- Execution plan: `plans/plan.md`
- Backend API (Python + FastAPI + local auth): `backend/` — not part of the visual system but defines the data model (expense: `amount`, `category`, `description`, `date`).

No Figma file was provided.

## What this is

A single-product consumer expense tracker — splits bills between friends and groups, tracks balances, shows activity history. The UI is adaptive: Material 3 on Android/Web, Cupertino on iOS, responsive desktop layout via `NavigationRail`.

## Index

- `colors_and_type.css` — CSS custom properties for colors, type scale, spacing, radii
- `preview/` — design system cards (colors, type, spacing, components)
- `ui_kits/mobile/` — Flutter-accurate React recreation of the mobile app
- `assets/` — logos / imagery placeholders (none shipped in the source codebase)
- `SKILL.md` — Agent-skill manifest (for Claude Code / skill system)
- `../frontend/` — imported Flutter source, kept for reference

## CONTENT FUNDAMENTALS

**Tone**: Friendly-utilitarian. Plain, no jargon, no marketing voice. Copy is **sentence-case**, never ALL CAPS, never title case (even in buttons: "Add expense", "Save expense", "Add friend").

**Person**: Second-person implicit — "you" as the active user. Balances read **"Overall, you are owed ₹1,250"** / **"Overall, you owe ₹340"** / **"You're all settled up"**. Never "I" or "we".

**Money**: Default currency is **INR**; the add-expense form shows `INR ` as a prefix. Amounts use Flutter's `tnum` feature — tabular, aligned. Examples on tiles: `"₹250.00"`, `"owes you ₹120"`, `"you owe ₹85"`.

**Empty states**: Short, directive. Examples from the code:
- Friends: "No friends yet" / "Your friend balances will appear here." / CTA "Add your first friend"
- Groups: "No groups yet" / "Create a group to split expenses with others." / CTA "Create group"
- Activity: silently renders an empty list (no hero copy)

**Buttons & labels**: Imperative verbs first — "Add expense", "Save expense", "Create group", "Add friend", "Edit". Sentence-case always.

**Settings labels**: Flat nouns — "Notifications", "Security", "Theme", "Help and feedback", "Logout".

**Emoji**: **Not used anywhere** in the source. Stay off emoji.

**Vibe**: Pragmatic, modern-utility. The product is a tool, not a destination — copy gets out of the way.

## VISUAL FOUNDATIONS

**Color**: Accent-driven Material 3. One seed color (green `#26A17B` in the default Splitwise family) drives the full `ColorScheme.fromSeed()` palette. Three theme families exist — Splitwise (green), Tokyo Night (blue `#7AA2F7`), Mint (`#3FBF9B`) — each with light / dark / high-contrast / custom variants. **Positive money** is always `#1B8C67` (a single hardcoded green, not theme-linked). **Negative money** uses `ColorScheme.error`.

**Backgrounds**: Solid. No gradients, no images, no textures, no patterns.
- Light scaffold: `#F7F8F9` (warm neutral off-white)
- Dark scaffold: `#111318` (near-black blue-black)
- High-contrast: pure white `#FFFFFF`
Cards sit on top as pure `#FFFFFF` (light) surfaces.

**Type**: Flutter default — **Roboto** on Android/Web, **SF Pro** (system) on iOS via Cupertino. **No custom fonts** are declared in `pubspec.yaml`. Material 3 text theme: headlineSmall for balances (24/700), titleMedium for section headers (16/500), bodyMedium for body (14/400), labelLarge for trailing amounts (14/500).

**Spacing**: 4/8/16/24 step system. `xs 4 • sm 8 • md 16 • lg 24`. Page padding is 16 (mobile ListView) and 24 horizontal + 20 top on desktop. Card internal padding is 16.

**Radii**: Flat and calm.
- Swatches / small surfaces: `8px`
- **Cards: `14px`** (defined once in `app_theme.dart` — `BorderRadius.circular(14)`)
- Cupertino pills / chips: `16px`
- Circle avatars / accent dots: full (999)

**Borders & shadows**: Cards use **elevation 0** (flat), with the background separation coming from scaffold-vs-surface contrast alone. No drop shadows on cards. The FAB gets the only real shadow in the app (Material default). Dividers are hairline `1px` at 12% black.

**Animation**: Default Flutter motion only — standard `PageRoute` slides, `IndexedStack` cross-fades. No custom tweens, no bounces. `NavigationBar` has a capsule indicator at 18% accent opacity (36% in high-contrast).

**Hover / press states**: No mouse-hover styling in the source — this is a mobile-first app. Touch feedback uses Material ripple (Android) and opacity dim (iOS). The `_AccentButton` color swatch uses `InkWell` with a `999px` border radius for a contained ripple.

**Transparency & blur**: None used. No frosted glass, no `backdrop-filter`. The Cupertino nav bar is the only translucent surface, and only because that's the platform default.

**Imagery**: **None in the source.** The app ships no illustrations, no hero art, no onboarding imagery — every surface is text + icons + color. Avatars are solid-color `CircleAvatar` with a Material icon inside.

**Cards — the dominant primitive**: Every row in the app is a `Card` with a `ListTile`. `leading` is a 40px circle (`CircleAvatar` with icon), `title` + `subtitle` in a column, `trailing` is either a money amount (labelLarge, colored) or a `chevron_right`.

**Layout rules**:
- Mobile: full-width ListView, 16px padding.
- Tablet/Desktop: centered column, `maxWidth: 900` (pages) or `760` (add-expense form).
- Breakpoints: mobile `<600` / tablet `<1024` / desktop `≥1024`.
- Desktop shell swaps `NavigationBar` (bottom) for `NavigationRail` (left, label-type: `all`).
- FAB (`Add expense`) sits bottom-right; hidden on the Account tab (`_showAddExpenseButton = _selectedIndex < 3`).

**Icon vibe**: Outlined by default, filled when selected (e.g. `Icons.person_outline` → `Icons.person` on active tab). On iOS, these map to Cupertino equivalents (`CupertinoIcons.person` / `person_fill`).

## ICONOGRAPHY

**System**: Material Icons (Android / Web) + Cupertino Icons (iOS) — both are **built into Flutter** (`uses-material-design: true`, `cupertino_icons: ^1.0.8`). No custom icon font, no custom SVG icon set, no icon assets are shipped in the repo.

**Style**: Outlined for inactive / secondary use; filled for selected / primary use. Stroke weight is Material's default (`~1.5` visual weight). The platform mapping is explicit — `home_shell_page.dart` maintains a `_toCupertinoIcon` switch that pairs each Material icon to its Cupertino counterpart.

**Inventory observed in source**:
- Nav: `person_outline/person`, `group_outlined/group`, `list_alt_outlined/list_alt`, `account_circle_outlined/account_circle`
- Rows & actions: `receipt_long`, `receipt_long_outlined`, `chevron_right`, `add` (FAB), `check` (save button)

**For the preview / UI kit**: We substitute **Lucide Icons** (CDN) as the closest match — similar outline style, modern stroke, wide coverage. This is flagged as a substitution; in production, use the platform Material/Cupertino icons directly.

**Emoji**: Not used. Don't add them.

**Unicode as icons**: Only `₹` for Indian Rupee. The app's default currency is INR.

**Logos / branding**: No brand mark exists in the codebase. Placeholder wordmark uses the product name set in `Roboto 700` + the accent green.

## Theme families

| Family | Light | Dark | High-contrast |
|---|---|---|---|
| Splitwise (default) | `#26A17B` | `#1A8F6C` | `#000000` |
| Tokyo Night | `#7AA2F7` | `#7DCFFF` | `#1D1D1D` |
| Mint | `#3FBF9B` | `#2FAE8E` | `#0B3D2E` |

Custom variant lets users pick from 5 preset swatches: green, blue, coral, amber, violet (see `theme_settings_page.dart`).

## Caveats

- No brand logo, illustrations, or imagery in the source — those surfaces are blank in the UI kit.
- No custom fonts — we rely on system Roboto / SF Pro. If you want a branded typeface, that's a new decision.
- Icon set is platform-bundled; the HTML UI kit substitutes Lucide as the closest CDN match.
- Figma was not provided; all extraction is from Dart source.
