#!/bin/bash
set -euo pipefail
# Mechanical asset sizing for Apple's icon catalog; the generated artwork stays unchanged.
sips -z 1024 1024 Design/AppIcon-source.png --out App/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
sips -g pixelWidth -g pixelHeight App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
