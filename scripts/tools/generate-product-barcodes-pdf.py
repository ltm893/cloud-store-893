#!/usr/bin/env python3
"""Generate docs/product-barcodes.pdf from product rows in scripts/db/seed.sql."""

from __future__ import annotations

import re
import sys
from io import BytesIO
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SEED_SQL = ROOT / "scripts" / "db" / "seed.sql"
OUTPUT_PDF = ROOT / "docs" / "product-barcodes.pdf"

INSERT_RE = re.compile(
    r"INSERT INTO products\s*\([^)]+\)\s*VALUES\s*\(\s*"
    r"'([^']+)'\s*,\s*'((?:''|[^'])*)'\s*,\s*'([^']*)'",
    re.IGNORECASE,
)


def load_products() -> list[dict[str, str]]:
    text = SEED_SQL.read_text(encoding="utf-8")
    products: list[dict[str, str]] = []
    for barcode, name, product_type in INSERT_RE.findall(text):
        products.append(
            {
                "barcode": barcode,
                "name": name.replace("''", "'"),
                "product_type": product_type,
            }
        )
    if not products:
        raise SystemExit(f"No products found in {SEED_SQL}")
    return products


def render_pdf(products: list[dict[str, str]]) -> None:
    try:
        import barcode
        from barcode.writer import ImageWriter
        from PIL import Image
        from reportlab.lib.pagesizes import letter
        from reportlab.lib.units import inch
        from reportlab.pdfgen import canvas
    except ImportError as exc:
        raise SystemExit(
            "Missing dependencies. Install with:\n"
            "  pip3 install python-barcode pillow reportlab"
        ) from exc

    page_w, page_h = letter
    margin = 0.6 * inch
    cols = 2
    cell_w = (page_w - 2 * margin) / cols
    cell_h = 1.55 * inch
    rows_per_page = int((page_h - 2 * margin - 0.5 * inch) / cell_h)

    c = canvas.Canvas(str(OUTPUT_PDF), pagesize=letter)
    c.setTitle("Cloud Store 893 — Product Barcodes")

    def draw_header(page_num: int) -> None:
        c.setFont("Helvetica-Bold", 14)
        c.drawString(margin, page_h - margin, "Cloud Store 893 — Product Barcodes")
        c.setFont("Helvetica", 9)
        c.drawString(
            margin,
            page_h - margin - 14,
            f"Source: scripts/db/seed.sql · {len(products)} products · Page {page_num}",
        )

    page_num = 1
    draw_header(page_num)
    index = 0

    for i, product in enumerate(products):
        row = index // cols
        col = index % cols

        if row >= rows_per_page:
            c.showPage()
            page_num += 1
            draw_header(page_num)
            index = 0
            row = 0
            col = 0

        x = margin + col * cell_w
        y_top = page_h - margin - 0.45 * inch - row * cell_h
        y = y_top - cell_h

        code = product["barcode"]
        writer = ImageWriter()
        writer.set_options(
            {
                "module_width": 0.22,
                "module_height": 12.0,
                "font_size": 9,
                "text_distance": 3.0,
                "quiet_zone": 2.0,
            }
        )
        barcode_cls = barcode.get_barcode_class("code128")
        img = barcode_cls(code, writer=writer)
        buf = BytesIO()
        img.write(buf)
        buf.seek(0)
        pil = Image.open(buf).convert("RGB")

        img_w = min(cell_w - 0.25 * inch, 3.0 * inch)
        img_h = img_w * (pil.height / pil.width)
        img_x = x + (cell_w - img_w) / 2
        img_y = y + cell_h - img_h - 0.35 * inch
        c.drawInlineImage(pil, img_x, img_y, width=img_w, height=img_h)

        c.setFont("Helvetica-Bold", 8.5)
        title = product["name"]
        if len(title) > 44:
            title = title[:41] + "..."
        c.drawCentredString(x + cell_w / 2, y + 0.18 * inch, title)

        c.setFont("Helvetica", 7.5)
        c.drawCentredString(
            x + cell_w / 2,
            y + 0.05 * inch,
            f"{product['product_type']} · scan: {code}",
        )

        index += 1

    c.save()


def main() -> None:
    products = load_products()
    OUTPUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    render_pdf(products)
    print(f"Wrote {OUTPUT_PDF} ({len(products)} barcodes)")


if __name__ == "__main__":
    main()
