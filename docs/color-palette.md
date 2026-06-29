# Color palette

Shared brand colors for the web POS, admin UI (including the unauthorized **Platform** tab on `/admin/login.html`), and native clients. Prefer updating tokens in the files below rather than scattering hex literals in feature code.

**Sources of truth**

| Surface | File |
|---------|------|
| Admin + Platform tab | `public/admin/admin.css` (`:root`) |
| Login page (duplicate tokens) | `public/admin/login.html` (inline `:root`) |
| Cashier web POS | `public/style.css` (`:root`) |
| Android tablet | `android-pos/app/src/main/java/com/cloudstore/pos/ui/theme/Color.kt` |
| iOS tablet | `ios-pos/CloudStorePos/Views/PosPanelStyle.swift` |

When changing admin colors, update `admin.css` `:root` and keep `login.html` in sync (or remove the duplicate `:root` there). For app-wide Android changes, edit `Color.kt` and `Theme.kt` — see [AGENTS.md](../AGENTS.md).

---

## Core brand palette

Used across admin, cashier web, and Android (light theme).

| Swatch | Hex | CSS token | Role |
|--------|-----|-----------|------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#faf3df;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#faf3df` | `--bg` | Page background (cream) |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#ffffff;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#ffffff` | `--panel` | Cards, panels, buttons |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#872434;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#872434` | `--accent` (admin) / `--primary` (POS) | Burgundy — titles, active tabs, primary actions |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#114b5f;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#114b5f` | `--accent-2` (admin) / `--teal` (POS) | Teal — section headings, links, secondary buttons |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#1f2937;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#1f2937` | `--text` | Body text |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#6b7280;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#6b7280` | `--muted` | Labels, hints, inactive tabs |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#e5e7eb;border:1px solid #d1d5db;border-radius:4px;vertical-align:middle"></span> | `#e5e7eb` | `--border` | Borders, dividers |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#b42318;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#b42318` | `--danger` | Errors, failures |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#a8d5d1;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#a8d5d1` | `--highlight` / `--table-header-teal` | Table headers, numpad keys |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:rgba(168,213,209,0.25);border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `rgba(168, 213, 209, 0.25)` | `--highlight-panel` | Tinted content panels |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f5e7e9;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f5e7e9` | `--long-press` | Selected / long-press row tint |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#e3f4f2;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#e3f4f2` | `--till-active-row-teal` | Active till row background |

---

## Platform tab (unauthorized login)

`/admin/login.html` — **Platform** tab before sign-in. Styles: `public/admin/admin.css` (`.systems-*`, `.login-tab-*`) plus inline rules in `login.html`.

| Swatch | Hex | Token / selector | Used for |
|--------|-----|------------------|----------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#faf3df;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#faf3df` | `var(--bg)` | Full viewport behind login card |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#ffffff;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#ffffff` | `var(--panel)` | Main login / Platform card |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#872434;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#872434` | `var(--accent)` | “Cloud Store 893”, active Platform tab + underline |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#6b7280;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#6b7280` | `var(--muted)` | Inactive Sign in tab |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#e5e7eb;border:1px solid #d1d5db;border-radius:4px;vertical-align:middle"></span> | `#e5e7eb` | `.login-tabs` border (same as `--border`) | Tab divider |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#114b5f;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#114b5f` | `var(--accent-2)` | Section headings, Refresh button, repo links |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#1f2937;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#1f2937` | `var(--text)` | Description, build info, OCI IDs |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#faf3df;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#faf3df` | `var(--bg)` on inner cards | Android tablet + OCI resource cards |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#067647;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#067647` | `.systems-ok` | Healthy routes, green status dots |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#b54708;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#b54708` | `.systems-warning` | Warning status |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#b42318;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#b42318` | `var(--danger)` / `.systems-fail` | Failed routes, error dots |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#ffffff;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#ffffff` | — | Button label on filled burgundy/teal buttons |

---

## Admin-only extras

Authenticated admin UI (`public/admin/admin.css`) — approvals, till summaries, nav.

| Swatch | Hex | Role |
|--------|-----|------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f5e7e9;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f5e7e9` | Active side-nav table button |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#fef3f2;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#fef3f2` | Approvals forbidden banner background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f5c2c0;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f5c2c0` | Error / deny borders |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#e8dcc8;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#e8dcc8` | Unknown approval badge background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#5c4a32;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#5c4a32` | Unknown approval badge text |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#fafbfc;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#fafbfc` | Approval till summary default |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#b8dfd8;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#b8dfd8` | Cash till summary border |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f3fbf9;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f3fbf9` | Cash till summary background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#d4dceb;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#d4dceb` | Credit till summary border |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f6f8fc;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f6f8fc` | Credit till summary background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#fffaf2;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#fffaf2` | Unknown till summary background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#0d7a6f;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#0d7a6f` | Cash mode badge |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#4a5d8c;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#4a5d8c` | Credit mode badge |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#fff5f5;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#fff5f5` | Denied approval last-action banner |

---

## Cashier web extras

`public/style.css` — overlays and feedback not in `:root`.

| Swatch | Hex | Role |
|--------|-----|------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:rgba(15,23,42,0.55);border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `rgba(15, 23, 42, 0.55)` | Auth overlay scrim |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:rgba(0,0,0,0.35);border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `rgba(0, 0, 0, 0.35)` | Drawer backdrop |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:rgba(135,36,52,0.25);border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `rgba(135, 36, 52, 0.25)` | Burgundy focus ring |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#ecfdf5;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#ecfdf5` | Success toast background |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#047857;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#047857` | Success toast text |

---

## Android (`Color.kt`)

Light theme matches the web tokens above. Kotlin names map as follows:

| Swatch | Hex | Kotlin (light) |
|--------|-----|----------------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#faf3df;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#faf3df` | `PosBackground` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#ffffff;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#ffffff` | `PosPanel` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#872434;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#872434` | `PosPrimary` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#114b5f;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#114b5f` | `PosAccent` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#1f2937;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#1f2937` | `PosText` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#6b7280;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#6b7280` | `PosMuted` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#e5e7eb;border:1px solid #d1d5db;border-radius:4px;vertical-align:middle"></span> | `#e5e7eb` | `PosBorder` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#b42318;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#b42318` | `PosDanger` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#a8d5d1;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#a8d5d1` | `PosHighlight` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f5e7e9;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#f5e7e9` | `PosLongPress` |

**Dark theme** (`Color.kt`):

| Swatch | Hex | Kotlin |
|--------|-----|--------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#1a1210;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#1a1210` | `PosBackgroundDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#2a2420;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#2a2420` | `PosPanelDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#d4606f;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#d4606f` | `PosPrimaryDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#4a9eb5;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#4a9eb5` | `PosAccentDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f3f4f6;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#f3f4f6` | `PosTextDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#9ca3af;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#9ca3af` | `PosMutedDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#4b5563;border:1px solid #374151;border-radius:4px;vertical-align:middle"></span> | `#4b5563` | `PosBorderDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#f87171;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#f87171` | `PosDangerDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#1e3540;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#1e3540` | `PosHighlightDark` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#3a1f22;border:1px solid #4b5563;border-radius:4px;vertical-align:middle"></span> | `#3a1f22` | `PosLongPressDark` |

---

## iOS (`PosPanelStyle.swift`)

| Swatch | Hex | Swift | Notes |
|--------|-----|-------|-------|
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#faf3df;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#faf3df` | `PosColors.cream` | Matches web `--bg` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#872434;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#872434` | `PosColors.burgundy` | Matches `--accent` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#006d77;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#006d77` | `PosColors.teal` | **Differs** from web `#114b5f` |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:#a8d5d1;border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `#a8d5d1` | `PosColors.numpadKey` | Matches highlight teal |
| <span style="display:inline-block;width:1.5em;height:1.5em;background:rgba(0,0,0,0.75);border:1px solid #e5e7eb;border-radius:4px;vertical-align:middle"></span> | `black @ 75%` | `PosColors.panelBorder` | Panel stroke |

---

## Changing colors

1. **Web admin / Platform tab** — edit `:root` in `public/admin/admin.css`; mirror in `public/admin/login.html` if needed.
2. **Cashier web** — edit `:root` in `public/style.css`.
3. **Android** — edit `Color.kt` and `Theme.kt`; use `MaterialTheme.colorScheme.*` in composables.
4. **Keep surfaces coherent** — page chrome uses `background`; cards use `surface` / `panel`. Avoid one-off hex in feature screens unless documented.

See [AGENTS.md](../AGENTS.md) for agent guidance on theme changes.
