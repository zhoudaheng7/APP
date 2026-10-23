import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[1] / 'App' / 'Assets.xcassets'
folder = root / 'AppIcon.appiconset'
folder.mkdir(parents=True, exist_ok=True)
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}), encoding='utf-8')
size = 1024
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        t = (x + y) / 2046
        pixels[x, y] = (int(29 + 40*t), int(84 + 72*t), int(56 + 18*t))
glass = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(glass)
draw.rounded_rectangle((180, 180, 844, 844), radius=178, fill=(232, 255, 214, 20), outline=(235, 255, 220, 135), width=3)
draw.line((340, 688, 690, 338), fill=(242, 255, 226, 255), width=62)
draw.line([(443, 336), (690, 336), (690, 583)], fill=(242, 255, 226, 255), width=62, joint='curve')
draw.ellipse((310, 658, 372, 720), fill=(242, 255, 226, 255))
image = Image.alpha_composite(image.convert('RGBA'), glass).convert('RGB')
image.save(folder / 'AppIcon.png', optimize=True)
(folder / 'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}, indent=2),encoding='utf-8')
print('Native app icon generated')
