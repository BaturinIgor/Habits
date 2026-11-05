#!/usr/bin/env python3
"""Делает скриншоты для App Store 1320x2868 (iPhone 6.9") из обычных скриншотов с любого iPhone.

Скриншот уменьшается, получает скруглённые углы и тень и кладётся на фон в цветах иконки,
сверху крупная подпись из docs/appstore/screenshots/captions.tsv.

    pip install pillow
    python3 tools/appstore/make_screenshots.py --input raw/ru --lang ru --out out/ru --font /path/to/Bold.ttf

В папке --input файлы 01.png, 02.png ... (номера как в captions.tsv). Шрифт нужен с кириллицей
(и с иероглифами, если делаешь китайский, японский или корейский).
"""
import argparse
import csv
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
TOP = (139, 116, 240)      # фиолетовый из иконки
BOTTOM = (69, 156, 244)    # голубой из иконки
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))


def gradient():
    img = Image.new('RGB', (W, H))
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def load_captions(lang):
    path = os.path.join(ROOT, 'docs/appstore/screenshots/captions.tsv')
    rows = [line for line in open(path, encoding='utf-8') if line.strip() and not line.startswith('#')]
    table = list(csv.DictReader(rows, delimiter='\t'))
    if lang not in table[0]:
        sys.exit(f'В captions.tsv нет колонки {lang}. Есть: {", ".join(k for k in table[0] if k != "num")}')
    return {row['num']: row[lang] for row in table}


def fit_font(path, text, max_width, size):
    while size > 40:
        font = ImageFont.truetype(path, size)
        if max(font.getlength(line) for line in text) <= max_width:
            return font
        size -= 4
    return ImageFont.truetype(path, size)


def compose(shot_path, caption, font_path):
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)

    lines = [part.strip() for part in caption.split('|')]
    font = fit_font(font_path, lines, W - 160, 112)
    y = 170
    for line in lines:
        width = font.getlength(line)
        draw.text(((W - width) / 2, y), line, font=font, fill='white')
        y += int(font.size * 1.18)

    shot = Image.open(shot_path).convert('RGB')
    target_h = H - y - 150
    scale = min((W - 200) / shot.width, target_h / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    radius = round(shot.width * 0.11)
    mask = Image.new('L', shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius, fill=255)

    x = (W - shot.width) // 2
    top = y + 70
    shadow = Image.new('L', (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([x, top + 24, x + shot.width, top + shot.height + 24], radius, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.paste(Image.new('RGB', (W, H), (30, 30, 80)), (0, 0), shadow)
    canvas.paste(shot, (x, top), mask)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--input', required=True, help='папка с 01.png, 02.png ...')
    parser.add_argument('--lang', default='en-US', help='колонка из captions.tsv')
    parser.add_argument('--out', required=True)
    parser.add_argument('--font', required=True, help='жирный TTF/OTF шрифт')
    args = parser.parse_args()

    captions = load_captions(args.lang)
    os.makedirs(args.out, exist_ok=True)
    done = 0
    for num, caption in sorted(captions.items()):
        for ext in ('png', 'jpg', 'jpeg', 'PNG', 'JPG'):
            src = os.path.join(args.input, f'{num}.{ext}')
            if os.path.exists(src):
                out = os.path.join(args.out, f'{num}.png')
                compose(src, caption, args.font).save(out, optimize=True)
                print(f'{src} -> {out}')
                done += 1
                break
    if not done:
        sys.exit('Не нашёл ни одного скриншота с номером из captions.tsv')


if __name__ == '__main__':
    main()
