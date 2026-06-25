#!/usr/bin/env bash
# Compatibility wrapper — use scripts/tools/generate-product-barcodes-pdf.py
exec node "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/generate-product-barcodes-pdf.py" "$@"
