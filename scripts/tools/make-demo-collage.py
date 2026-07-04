#!/usr/bin/env python3
"""Stitch ordered screenshots into a single demo JPG with a title."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
STEP_RE = re.compile(r"^(\d+)")

# Brand palette — docs/color-palette.md / Color.kt
COLOR_BURGUNDY = "#872434"
COLOR_LIGHT_TEAL = "#a8d5d1"
COLOR_TEAL = "#114b5f"
COLOR_TEXT = "#1f2937"
COLOR_MUTED = "#6b7280"
COLOR_BORDER = "#e5e7eb"
COLOR_PANEL = "#ffffff"
COLOR_TITLE_TEXT = "#ffffff"


def load_images(input_dir: Path) -> list[Path]:
    files = [p for p in input_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS]
    if not files:
        raise SystemExit(f"No images found in {input_dir}")
    return sorted(files, key=lambda p: p.name.lower())


def step_number(path: Path) -> int | None:
    match = STEP_RE.match(path.name)
    return int(match.group(1)) if match else None


def step_label(path: Path) -> str:
    stem = path.stem
    match = re.match(r"^\d+-(.+)$", stem)
    if not match:
        return stem
    words = re.sub(r"([a-z])([A-Z])", r"\1 \2", match.group(1))
    return words.replace("_", " ").replace("-", " ")


def load_intro(path: Path) -> list[tuple[str, str]]:
    """Parse intro blocks before the first numbered step heading."""
    if not path.exists():
        return []

    blocks: list[tuple[str, str]] = []
    current_body: list[str] = []

    def flush_body() -> None:
        nonlocal current_body
        if current_body:
            blocks.append(("body", " ".join(current_body)))
            current_body = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if re.match(r"^#{2,3}\s+\d", line):
            break
        if not line or line.startswith("# ") or line.startswith("!["):
            flush_body()
            continue
        if line == "Description":
            flush_body()
            blocks.append(("heading", line))
            continue
        if line.startswith("Source Code Repo:"):
            flush_body()
            blocks.append(("repo", line))
            continue
        if re.match(r"^\d+\.\s", line):
            flush_body()
            blocks.append(("list", line))
            continue
        current_body.append(line)

    flush_body()
    return blocks


def draw_intro_block(
    draw,
    *,
    x: int,
    y: int,
    max_width: int,
    blocks: list[tuple[str, str]],
    heading_font,
    body_font,
    repo_font,
    line_spacing: int,
) -> int:
    cursor_y = y
    list_indent = 18

    for kind, text in blocks:
        if kind == "heading":
            draw.text((x, cursor_y), text, fill=COLOR_BURGUNDY, font=heading_font)
            bbox = draw.textbbox((0, 0), "Ay", font=heading_font)
            cursor_y += (bbox[3] - bbox[1]) + 10
            continue

        font = repo_font if kind == "repo" else body_font
        fill = COLOR_TEAL if kind == "repo" else COLOR_TEXT
        block_x = x + (list_indent if kind == "list" else 0)
        block_width = max_width - (list_indent if kind == "list" else 0)
        for line in wrap_text(draw, text, font, block_width):
            draw.text((block_x, cursor_y), line, fill=fill, font=font)
            bbox = draw.textbbox((0, 0), "Ay", font=font)
            cursor_y += (bbox[3] - bbox[1]) + line_spacing
        cursor_y += 6

    return cursor_y - y


def load_descriptions(path: Path) -> dict[int, str]:
    """Parse step descriptions from DemoDescription (plain or markdown)."""
    if not path.exists():
        return {}

    descriptions: dict[int, str] = {}
    current_step: int | None = None
    body_lines: list[str] = []

    def flush() -> None:
        nonlocal current_step, body_lines
        if current_step is None:
            return
        text = " ".join(line.strip() for line in body_lines if line.strip())
        if text:
            descriptions[current_step] = text
        current_step = None
        body_lines = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("---"):
            continue
        if line.startswith("#") and not re.match(r"^#{2,3}\s+\d", line):
            continue
        if line.startswith("!["):
            continue
        if line.lower().startswith("image:"):
            continue

        plain = re.match(r"^(\d{1,2})\s+(.+)$", line)
        if plain:
            flush()
            current_step = int(plain.group(1))
            body_lines = [plain.group(2).strip()]
            continue

        heading = re.match(r"^#{2,3}\s+(\d{1,2})\b", line)
        if heading:
            flush()
            current_step = int(heading.group(1))
            continue

        if current_step is not None:
            body_lines.append(line)

    flush()
    return descriptions


def description_for(path: Path, descriptions: dict[int, str]) -> str:
    number = step_number(path)
    if number is not None and number in descriptions:
        return descriptions[number]
    return step_label(path)


def find_font(size: int, *, bold: bool = False):
    from PIL import ImageFont

    candidates = []
    if bold:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            ]
        )
    candidates.extend(
        [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/Library/Fonts/Arial.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        ]
    )
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def wrap_text(draw, text: str, font, max_width: int) -> list[str]:
    words = text.split()
    if not words:
        return [""]

    lines: list[str] = []
    current: list[str] = []
    for word in words:
        trial = " ".join(current + [word])
        bbox = draw.textbbox((0, 0), trial, font=font)
        if bbox[2] - bbox[0] <= max_width:
            current.append(word)
        else:
            if current:
                lines.append(" ".join(current))
            current = [word]
    if current:
        lines.append(" ".join(current))
    return lines


def draw_text_block(
    draw,
    *,
    x: int,
    y: int,
    step: str,
    description: str,
    max_width: int,
    step_font,
    desc_font,
    line_spacing: int,
) -> int:
    step_lines = wrap_text(draw, step, step_font, max_width)
    desc_lines = wrap_text(draw, description, desc_font, max_width)

    step_bbox = draw.textbbox((0, 0), "Ay", font=step_font)
    desc_bbox = draw.textbbox((0, 0), "Ay", font=desc_font)
    step_line_h = step_bbox[3] - step_bbox[1]
    desc_line_h = desc_bbox[3] - desc_bbox[1]

    cursor_y = y
    for line in step_lines:
        draw.text((x, cursor_y), line, fill=COLOR_BURGUNDY, font=step_font)
        cursor_y += step_line_h + 4

    cursor_y += 8
    for line in desc_lines:
        draw.text((x, cursor_y), line, fill=COLOR_TEXT, font=desc_font)
        cursor_y += desc_line_h + line_spacing

    return cursor_y - y


def make_slide(thumb, slide_padding: int):
    from PIL import Image, ImageDraw

    slide_w = thumb.width + slide_padding * 2
    slide_h = thumb.height + slide_padding * 2
    slide = Image.new("RGB", (slide_w, slide_h), COLOR_PANEL)
    slide.paste(thumb, (slide_padding, slide_padding))
    draw = ImageDraw.Draw(slide)
    draw.rectangle((0, 0, slide_w - 1, slide_h - 1), outline=COLOR_BORDER, width=1)
    return slide


def render_grid(
    images: list[Path],
    descriptions: dict[int, str],
    *,
    title: str,
    output: Path,
    cols: int,
    cell_width: int,
    padding: int,
    slide_padding: int,
    title_height: int,
    show_labels: bool,
    quality: int,
) -> None:
    from PIL import Image, ImageDraw

    rows = (len(images) + cols - 1) // cols
    labels = [description_for(p, descriptions) for p in images]

    sample = Image.open(images[0])
    aspect = sample.height / sample.width
    cell_height = int(cell_width * aspect)
    slide_w = cell_width + slide_padding * 2
    slide_h = cell_height + slide_padding * 2
    label_height = 28 if show_labels else 0

    grid_w = cols * slide_w + (cols - 1) * padding
    grid_h = rows * (slide_h + label_height) + (rows - 1) * padding
    canvas_w = grid_w + padding * 2
    canvas_h = title_height + grid_h + padding * 2

    canvas = Image.new("RGB", (canvas_w, canvas_h), COLOR_LIGHT_TEAL)
    draw = ImageDraw.Draw(canvas)

    title_font = find_font(34)
    label_font = find_font(16)

    draw.rectangle((0, 0, canvas_w, title_height), fill=COLOR_BURGUNDY)
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_x = (canvas_w - (title_bbox[2] - title_bbox[0])) // 2
    title_y = (title_height - (title_bbox[3] - title_bbox[1])) // 2
    draw.text((title_x, title_y), title, fill=COLOR_TITLE_TEXT, font=title_font)

    origin_x = padding
    origin_y = title_height + padding

    for index, path in enumerate(images):
        row = index // cols
        col = index % cols
        x = origin_x + col * (slide_w + padding)
        y = origin_y + row * (slide_h + label_height + padding)

        with Image.open(path) as img:
            thumb = img.convert("RGB").resize((cell_width, cell_height), Image.Resampling.LANCZOS)
        slide = make_slide(thumb, slide_padding)
        canvas.paste(slide, (x, y))

        if show_labels:
            label = labels[index]
            label_bbox = draw.textbbox((0, 0), label, font=label_font)
            label_x = x + (slide_w - (label_bbox[2] - label_bbox[0])) // 2
            label_y = y + slide_h + 6
            draw.text((label_x, label_y), label, fill=COLOR_TEXT, font=label_font)

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="JPEG", quality=quality, optimize=True)
    print(f"Wrote {output} ({canvas_w}x{canvas_h})")


def render_vertical(
    images: list[Path],
    descriptions: dict[int, str],
    intro_blocks: list[tuple[str, str]],
    *,
    title: str,
    output: Path,
    cell_width: int,
    text_width: int,
    padding: int,
    slide_padding: int,
    title_height: int,
    row_gap: int,
    intro_gap: int,
    quality: int,
) -> None:
    from PIL import Image, ImageDraw

    labels = [description_for(p, descriptions) for p in images]
    sample = Image.open(images[0])
    aspect = sample.height / sample.width
    cell_height = int(cell_width * aspect)
    slide_w = cell_width + slide_padding * 2
    slide_h = cell_height + slide_padding * 2

    text_x = padding
    image_x = padding + text_width + padding
    canvas_w = image_x + slide_w + padding
    intro_width = canvas_w - padding * 2

    step_font = find_font(28, bold=True)
    desc_font = find_font(18)
    title_font = find_font(34)
    intro_heading_font = find_font(26, bold=True)
    intro_body_font = find_font(18)
    intro_repo_font = find_font(18, bold=True)

    probe = Image.new("RGB", (1, 1))
    probe_draw = ImageDraw.Draw(probe)

    intro_panel_padding = 20
    intro_inner_h = 0
    if intro_blocks:
        intro_inner_h = draw_intro_block(
            probe_draw,
            x=0,
            y=0,
            max_width=intro_width - intro_panel_padding * 2,
            blocks=intro_blocks,
            heading_font=intro_heading_font,
            body_font=intro_body_font,
            repo_font=intro_repo_font,
            line_spacing=6,
        )
    intro_panel_h = intro_inner_h + intro_panel_padding * 2 if intro_blocks else 0

    row_heights: list[int] = []
    text_heights: list[int] = []
    for index, label in enumerate(labels):
        number = step_number(images[index]) or (index + 1)
        text_h = draw_text_block(
            probe_draw,
            x=0,
            y=0,
            step=f"{number:02d}",
            description=label,
            max_width=text_width,
            step_font=step_font,
            desc_font=desc_font,
            line_spacing=4,
        )
        text_heights.append(text_h)
        row_heights.append(max(slide_h, text_h))

    body_h = sum(row_heights) + row_gap * (len(images) - 1)
    intro_section_h = intro_panel_h + (intro_gap if intro_blocks else 0)
    canvas_h = title_height + padding + intro_section_h + body_h + padding

    canvas = Image.new("RGB", (canvas_w, canvas_h), COLOR_LIGHT_TEAL)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle((0, 0, canvas_w, title_height), fill=COLOR_BURGUNDY)
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_x = (canvas_w - (title_bbox[2] - title_bbox[0])) // 2
    title_y = (title_height - (title_bbox[3] - title_bbox[1])) // 2
    draw.text((title_x, title_y), title, fill=COLOR_TITLE_TEXT, font=title_font)

    cursor_y = title_height + padding
    if intro_blocks:
        panel_x = padding
        panel_y = cursor_y
        draw.rectangle(
            (panel_x, panel_y, panel_x + intro_width, panel_y + intro_panel_h),
            fill=COLOR_PANEL,
            outline=COLOR_BORDER,
            width=1,
        )
        draw_intro_block(
            draw,
            x=panel_x + intro_panel_padding,
            y=panel_y + intro_panel_padding,
            max_width=intro_width - intro_panel_padding * 2,
            blocks=intro_blocks,
            heading_font=intro_heading_font,
            body_font=intro_body_font,
            repo_font=intro_repo_font,
            line_spacing=6,
        )
        cursor_y += intro_panel_h + intro_gap
        draw.line((padding, cursor_y - intro_gap // 2, canvas_w - padding, cursor_y - intro_gap // 2), fill=COLOR_BORDER, width=1)

    for index, path in enumerate(images):
        row_h = row_heights[index]
        label = labels[index]
        number = step_number(path) or (index + 1)
        step = f"{number:02d}"

        text_y = cursor_y + (row_h - text_heights[index]) // 2
        image_y = cursor_y + (row_h - slide_h) // 2
        draw_text_block(
            draw,
            x=text_x,
            y=text_y,
            step=step,
            description=label,
            max_width=text_width,
            step_font=step_font,
            desc_font=desc_font,
            line_spacing=4,
        )

        with Image.open(path) as img:
            thumb = img.convert("RGB").resize((cell_width, cell_height), Image.Resampling.LANCZOS)
        slide = make_slide(thumb, slide_padding)
        canvas.paste(slide, (image_x, image_y))

        divider_y = cursor_y + row_h + row_gap // 2
        if index < len(images) - 1:
            draw.line((padding, divider_y, canvas_w - padding, divider_y), fill=COLOR_BORDER, width=1)

        cursor_y += row_h + row_gap

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="JPEG", quality=quality, optimize=True)
    print(f"Wrote {output} ({canvas_w}x{canvas_h})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=ROOT / "docs" / "demos" / "images01",
        help="Folder of ordered screenshots (default: docs/demos/images01)",
    )
    parser.add_argument(
        "--descriptions",
        type=Path,
        default=ROOT / "docs" / "demos" / "DemoDescription",
        help="Step descriptions file (default: docs/demos/DemoDescription)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "docs" / "demos" / "cloud-store-demo-split-trans-linked-cust.jpg",
        help="Output JPG path",
    )
    parser.add_argument(
        "--title",
        default="Cloud Store POS — Split Transaction with Linked Customer",
        help="Title text across the top",
    )
    parser.add_argument(
        "--layout",
        choices=("vertical", "grid"),
        default="vertical",
        help="vertical = text left, images stacked; grid = thumbnail grid (default: vertical)",
    )
    parser.add_argument("--cols", type=int, default=3, help="Grid columns when --layout grid")
    parser.add_argument("--cell-width", type=int, default=600, help="Width of each screenshot")
    parser.add_argument("--text-width", type=int, default=300, help="Text column width when vertical")
    parser.add_argument("--padding", type=int, default=24, help="Outer padding (px)")
    parser.add_argument("--slide-padding", type=int, default=20, help="Padding around each image slide (px)")
    parser.add_argument("--row-gap", type=int, default=32, help="Space between vertical rows (px)")
    parser.add_argument("--intro-gap", type=int, default=36, help="Space below intro panel (px)")
    parser.add_argument("--title-height", type=int, default=80, help="Title bar height (px)")
    parser.add_argument("--no-labels", action="store_true", help="Hide labels under images in grid layout")
    parser.add_argument("--quality", type=int, default=90, help="JPEG quality (default: 90)")
    parser.add_argument(
        "--full-width",
        action="store_true",
        help="Wider layout (~1900px) for full-screen browser viewing",
    )
    args = parser.parse_args()

    if args.full_width:
        args.cell_width = 1400
        args.text_width = 420
        args.padding = 32
        args.slide_padding = 24
        args.row_gap = 40
        args.intro_gap = 40
        args.title_height = 96

    try:
        from PIL import Image  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "Missing Pillow. Install with:\n"
            "  pip3 install pillow\n"
            "Or use: .venv-barcode/bin/python3 scripts/tools/make-demo-collage.py"
        ) from exc

    images = load_images(args.input_dir)
    descriptions = load_descriptions(args.descriptions)
    intro_blocks = load_intro(args.descriptions)
    if args.layout == "vertical":
        render_vertical(
            images,
            descriptions,
            intro_blocks,
            title=args.title,
            output=args.output,
            cell_width=args.cell_width,
            text_width=args.text_width,
            padding=args.padding,
            slide_padding=args.slide_padding,
            title_height=args.title_height,
            row_gap=args.row_gap,
            intro_gap=args.intro_gap,
            quality=args.quality,
        )
    else:
        render_grid(
            images,
            descriptions,
            title=args.title,
            output=args.output,
            cols=args.cols,
            cell_width=args.cell_width,
            padding=args.padding,
            slide_padding=args.slide_padding,
            title_height=args.title_height,
            show_labels=not args.no_labels,
            quality=args.quality,
        )


if __name__ == "__main__":
    main()
