# Mobile UI Kit

A React recreation of the Flutter `expense_tracker` mobile app.

## Source

- `frontend/lib/app/view/home_shell_page.dart` — adaptive shell (Material / Cupertino)
- `frontend/lib/features/{friends,groups,activity,account,expenses,theme}/view/`
- `frontend/lib/core/theme/app_theme.dart` — ThemeData build + accent logic
- `frontend/lib/features/dashboard/models/dashboard_snapshot.dart` — data shape

## Screens

1. **Friends** — overall summary + balances list (`owes you` / `you owe`)
2. **Groups** — overall summary + group balance rows
3. **Activity** — recent expense events
4. **Account** — profile + settings rows (Notifications, Security, Theme, Help, Logout)
5. **Add expense** — modal form (description, INR amount, paid-by, split)
6. **Theme settings** — family dropdown, variant segmented control, live preview, custom accent swatches

## Files

- `Components.jsx` — `Avatar`, `Card`, `ListTile`, `SummaryCard`, `SectionHeader`, `MoneyLabel`, `AppBar`, `BottomNav`, `Fab`, `FilledButton`, `TextButton`, `TextField`, `Chip`, `DropdownRow`, `Icon`
- `App.jsx` — page components + `MobileApp` shell
- `ios-frame.jsx` / `android-frame.jsx` — device bezels
- `index.html` — renders Android + iOS side by side; tap tabs and the FAB to navigate

## Notes

- Material Icons / Cupertino Icons are inlined as SVGs hand-shaped to match the originals (person, group, list_alt, account_circle, receipt_long, chevron_right, add, check).
- Currency is INR; positive balances use `#1B8C67`, negative uses error red `#BA1A1A`.
- Data is a single `seed` object shaped like `DashboardSnapshot`.
