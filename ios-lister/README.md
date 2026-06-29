# Cloud Store Lister (iOS)

Native iOS inventory lookup for **Cloud Store 893** — Lister-style numpad input and product card, backed by the Node API (`GET /api/inventory/lookup`) instead of web scraping.

## What you get

- Numeric keypad: enter product **ID** or **barcode**, tap **Lookup**
- Product card: name, type, manufacturer, price, stock, reorder point
- Lister-aligned palette (burgundy / cream / teal)
- iPhone portrait; iPad portrait (inventory walk-around use)

No lists, CSV import, or camera scan in v1 — just lookup + display.

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- Apple Developer signing team

## API host (`API_BASE_URL`)

Default: `https://oci.cloudstore893.com/` via `Config/Debug.xcconfig` and `Config/Release.xcconfig`.

**Local Mac dev** (`npm run dev:up`):

```bash
npm run ios-lister:local-config
```

Or copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig`.

## Open and run

```bash
open ios-lister/CloudStoreLister.xcodeproj
```

Select iPhone or iPad simulator, set **Team**, Run. The lookup route is public (no cashier PIN required).

## API

`GET /api/inventory/lookup?q=<id-or-barcode>` returns one product with stock metadata. See `lib/inventory.js` (`mapProductForInventoryLookup`).

## Tests

```bash
npm run test:ios-lister
```

## Project layout

| Path | Purpose |
|------|---------|
| `CloudStoreLister/Views/InventoryLookupView.swift` | Main screen |
| `CloudStoreLister/API/InventoryAPIClient.swift` | HTTP client |
| `CloudStoreLister/Logic/InventoryDisplayLogic.swift` | Stock/price labels |
