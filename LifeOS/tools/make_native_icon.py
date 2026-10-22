"""Generate an original geometric icon without fonts or external assets."""
from pathlib import Path
import json, math, struct, zlib

size = 1024
rows = bytearray()
for y in range(size):
    rows.append(0)
    for x in range(size):
        dx, dy = (x - 510) / size, (y - 520) / size
        radial = min(1.0, math.hypot(dx, dy) * 1.4)
        base = [int(15 + 5 * radial), int(105 + 36 * (1 - radial)), int(113 + 21 * (1 - radial))]
        sun = math.hypot(x - 512, y - 462)
        ring = abs(sun - 220) < 19 and y < 555
        horizon = abs(y - 565) < 17 and 248 < x < 776
        reflection = (abs(y - 630) < 12 and 335 < x < 689) or (abs(y - 685) < 9 and 414 < x < 610)
        if ring or horizon or reflection:
            base = [231, 250, 237] if ring or horizon else [150, 220, 203]
        rows.extend(base)
def chunk(name, payload):
    return struct.pack('>I', len(payload)) + name + payload + struct.pack('>I', zlib.crc32(name + payload) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(rows), 7)) + chunk(b'IEND', b'')
folder = Path('NativeApp/Assets.xcassets/AppIcon.appiconset')
folder.mkdir(parents=True, exist_ok=True)
(folder / 'AppIcon.png').write_bytes(png)
(folder / 'Contents.json').write_text(json.dumps({'images': [{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info':{'author':'LifeOS','version':1}}), encoding='utf-8')
folder.parent.joinpath('Contents.json').write_text('{"info":{"author":"LifeOS","version":1}}', encoding='utf-8')
