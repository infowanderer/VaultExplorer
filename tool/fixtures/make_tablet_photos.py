"""Create public synthetic photo fixtures; no personal files are read.

Requires Pillow. Usage: python3 tool/fixtures/make_tablet_photos.py OUTPUT.zip
"""
from pathlib import Path
import io
import sys
import zipfile
from PIL import Image, ImageDraw, ImageFont


def make_archive(output):
    output = Path(output)
    if output.exists():
        raise FileExistsError('Refusing to overwrite an existing fixture archive')
    output.parent.mkdir(parents=True, exist_ok=True)
    readme = '''Media Organizer — synthetic tablet fixtures

These images are drawn test cards, not personal photographs.
Extract this ZIP to a disposable folder on internal storage, microSD or USB.
Open Photos in Media Organizer Preview and choose the photo-sorter toolbar icon.
Check thumbnails, tap/S Pen selection, zoom, arrows, Space and keys 1/2/3.
The sorter stages labels only. It does not move or copy your files yet.
Backgrounding the preview clears its in-memory staged labels by design.

12-rotated-exif.jpg should display upright after EXIF orientation handling.
invalid.jpg is deliberately broken; a placeholder or decode error is expected.
No personal metadata or GPS coordinates are included. All data may be discarded.
'''
    colors = [(37, 99, 155), (178, 93, 60), (58, 128, 102), (111, 83, 150)]
    sizes = [(1600, 900), (900, 1600), (1200, 1200), (2400, 800)]
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', 60)
        small = ImageFont.truetype('DejaVuSans.ttf', 28)
    except OSError:
        font = small = ImageFont.load_default()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        def add(name, data):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
        add('Tablet-Test-Photos/READ-ME.txt', readme.encode())
        for index in range(1, 13):
            size = sizes[(index - 1) % len(sizes)]
            if index == 12:
                size = (1600, 900)
            image = Image.new('RGB', size, colors[(index - 1) % len(colors)])
            draw = ImageDraw.Draw(image)
            draw.rectangle((35, 35, size[0] - 35, size[1] - 35), outline='white', width=8)
            draw.text((80, 100), f'TEST PHOTO {index:02}', fill='white', font=font)
            draw.text((80, 200), 'SYNTHETIC FIXTURE - NO PERSONAL MEDIA', fill='white', font=small)
            draw.polygon([(100, 400), (220, 280), (340, 400)], fill='white')
            draw.text((100, 440), 'UP', fill='white', font=font)
            exif = Image.Exif()
            exif[274] = 1
            name = f'{index:02}-test.jpg'
            if index == 12:
                image = image.rotate(90, expand=True)
                exif[274] = 6
                name = '12-rotated-exif.jpg'
            buffer = io.BytesIO()
            image.save(buffer, format='JPEG', quality=85, exif=exif)
            add('Tablet-Test-Photos/Photos/' + name, buffer.getvalue())
        add('Tablet-Test-Photos/Photos/invalid.jpg', b'intentionally invalid synthetic JPEG fixture\n')
        for folder in ('Keep', 'Share', 'Later'):
            add('Tablet-Test-Photos/Destinations/' + folder + '/', b'')
    print(output.resolve())


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    make_archive(sys.argv[1])
