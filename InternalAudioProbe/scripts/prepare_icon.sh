#!/bin/bash
set -euo pipefail
# Mechanical asset sizing for Apple's icon catalog; the generated artwork stays unchanged.
sips -z 1024 1024 Design/AppIcon-source.png --out App/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
sips -g pixelWidth -g pixelHeight App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
# Named image assets can be used in share previews even if re-signing changes the app identity.
cp App/Assets.xcassets/AppIcon.appiconset/AppIcon.png App/Assets.xcassets/ShareIcon.imageset/ShareIcon.png
