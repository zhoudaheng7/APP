"""Package generated artwork for Apple's asset catalog; preserve the source."""
from pathlib import Path
import json, subprocess

source = Path('Branding/dayisle-icon.png')
assert source.is_file(), 'Generated brand asset is missing'
assets = Path('NativeApp/Assets.xcassets')
for name, size in [('AppIcon.appiconset', 1024), ('BrandMark.imageset', 512)]:
    target = assets/name
    target.mkdir(parents=True, exist_ok=True)
    output = target/'dayisle.png'
    subprocess.run(['sips', '-z', str(size), str(size), '-s', 'format', 'png', str(source), '--out', str(output)], check=True)
    image = {'filename':'dayisle.png','idiom':'universal'}
    if 'appiconset' in name: image.update({'platform':'ios','size':'1024x1024'})
    (target/'Contents.json').write_text(json.dumps({'images':[image], 'info':{'author':'Dayisle','version':1}}), encoding='utf-8')
assets.joinpath('Contents.json').write_text('{"info":{"author":"Dayisle","version":1}}', encoding='utf-8')
