#!/usr/bin/env python3
"""Convert the demo collage JPG to a single-page PDF."""

from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        default=ROOT / "docs" / "demos" / "cloud-store-demo-split-trans-linked-cust.jpg",
        help="Input collage JPG",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "docs" / "demos" / "cloud-store-demo-split-trans-linked-cust.pdf",
        help="Output PDF path",
    )
    args = parser.parse_args()

    if not args.input.exists():
        raise SystemExit(f"Input not found: {args.input}")

    try:
        from PIL import Image
    except ImportError as exc:
        raise SystemExit(
            "Missing Pillow. Install with:\n"
            "  pip3 install pillow\n"
            "Or use: .venv-barcode/bin/python3 scripts/tools/make-demo-pdf.py"
        ) from exc

    with Image.open(args.input) as image:
        pdf_image = image.convert("RGB")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        pdf_image.save(args.output, format="PDF", resolution=150.0)

    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
