#!/usr/bin/env python3
"""Generate docs/stub-dance-shop-barcodes.pdf from Android POS stub catalog."""

from __future__ import annotations

from io import BytesIO
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUTPUT_PDF = ROOT / "docs" / "stub-dance-shop-barcodes.pdf"

# Keep in sync with android-pos/.../StubPosRepository.kt
PRODUCTS: list[dict[str, str]] = [
    {"barcode": "100000000001", "name": "Ballet Leotard — Black", "product_type": "apparel"},
    {"barcode": "100000000002", "name": "Tutu Skirt — Pink", "product_type": "apparel"},
    {"barcode": "100000000003", "name": "Jazz Shoes — Tan", "product_type": "footwear"},
    {"barcode": "100000000004", "name": "Ballet Slippers — Pink", "product_type": "footwear"},
    {"barcode": "100000000005", "name": "Character Skirt — Black", "product_type": "apparel"},
    {"barcode": "100000000006", "name": "Dance Tights — Nude", "product_type": "apparel"},
    {"barcode": "100000000007", "name": "Competition Dress — Navy", "product_type": "apparel"},
    {"barcode": "100000000008", "name": "Hair Bun Net Pack", "product_type": "accessories"},
    {"barcode": "100000000009", "name": "Warm-up Booties", "product_type": "footwear"},
    {"barcode": "100000000010", "name": "Gift Card $50", "product_type": "gift"},
]

# Bar / text color for the Code128 graphic (scanners still need strong contrast).
BAR_BLUE = (0, 90, 180)
PER_PAGE = 4
COLS = 2


def barcode_to_blue(pil_rgb):
    """Replace near-black barcode ink with blue; keep white background."""
    pixels = pil_rgb.load()
    w, h = pil_rgb.size
    for y in range(h):
        for x in range(w):
            r, g, b = pixels[x, y]
            if r < 80 and g < 80 and b < 80:
                pixels[x, y] = BAR_BLUE
    return pil_rgb


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
            "  pip3 install python-barcode pillow reportlab\n"
            "Or use: .venv-barcode/bin/python3 scripts/tools/generate-stub-dance-barcodes-pdf.py"
        ) from exc

    page_w, page_h = letter
    margin = 0.55 * inch
    header_h = 0.55 * inch
    cols = COLS
    rows = PER_PAGE // cols
    cell_w = (page_w - 2 * margin) / cols
    cell_h = (page_h - 2 * margin - header_h) / rows

    c = canvas.Canvas(str(OUTPUT_PDF), pagesize=letter)
    c.setTitle("Scouty's Store 893 — Stub Dance Shop Barcodes")

    total_pages = (len(products) + PER_PAGE - 1) // PER_PAGE

    for page_num in range(1, total_pages + 1):
        if page_num > 1:
            c.showPage()

        c.setFont("Helvetica-Bold", 14)
        c.drawString(margin, page_h - margin, "Scouty's Store 893 — Stub Dance Shop Barcodes")
        c.setFont("Helvetica", 9)
        c.drawString(
            margin,
            page_h - margin - 14,
            f"Android POS stub catalog · {len(products)} products · Page {page_num} of {total_pages}",
        )

        page_products = products[(page_num - 1) * PER_PAGE : page_num * PER_PAGE]
        for index, product in enumerate(page_products):
            row = index // cols
            col = index % cols
            x = margin + col * cell_w
            y = page_h - margin - header_h - (row + 1) * cell_h

            code = product["barcode"]
            writer = ImageWriter()
            writer.set_options(
                {
                    "module_width": 0.28,
                    "module_height": 16.0,
                    "font_size": 10,
                    "text_distance": 3.5,
                    "quiet_zone": 2.5,
                }
            )
            barcode_cls = barcode.get_barcode_class("code128")
            img = barcode_cls(code, writer=writer)
            buf = BytesIO()
            img.write(buf)
            buf.seek(0)
            pil = barcode_to_blue(Image.open(buf).convert("RGB"))

            img_w = min(cell_w - 0.3 * inch, 3.4 * inch)
            img_h = img_w * (pil.height / pil.width)
            img_x = x + (cell_w - img_w) / 2
            img_y = y + cell_h - img_h - 0.55 * inch
            c.drawInlineImage(pil, img_x, img_y, width=img_w, height=img_h)

            c.setFont("Helvetica-Bold", 10)
            title = product["name"]
            if len(title) > 36:
                title = title[:33] + "..."
            c.drawCentredString(x + cell_w / 2, y + 0.32 * inch, title)

            c.setFont("Helvetica", 8.5)
            c.drawCentredString(
                x + cell_w / 2,
                y + 0.14 * inch,
                f"{product['product_type']} · scan: {code}",
            )

    c.save()


def main() -> None:
    OUTPUT_PDF.parent.mkdir(parents=True, exist_ok=True)
    render_pdf(PRODUCTS)
    pages = (len(PRODUCTS) + PER_PAGE - 1) // PER_PAGE
    print(f"Wrote {OUTPUT_PDF} ({len(PRODUCTS)} barcodes, {pages} pages, {PER_PAGE}/page)")


if __name__ == "__main__":
    main()
