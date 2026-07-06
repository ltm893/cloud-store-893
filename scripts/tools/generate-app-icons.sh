#!/usr/bin/env bash
# Install Cloud Store 893 app icons from assets/icons/ into iOS and Android projects.
# Sources are 1024×1024 PNGs (cash-register, admin-console, lister).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ICONS="$ROOT/assets/icons"

install_android() {
  local src="$1"
  local res_dir="$2"
  local densities=(mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192)

  for entry in "${densities[@]}"; do
    local density="${entry%%:*}"
    local size="${entry##*:}"
    local dir="$res_dir/mipmap-$density"
    mkdir -p "$dir"
    sips -z "$size" "$size" "$src" --out "$dir/ic_launcher.png" >/dev/null
    cp "$dir/ic_launcher.png" "$dir/ic_launcher_round.png"
  done
}

install_ios() {
  local src="$1"
  local appiconset="$2"
  cp "$src" "$appiconset/AppIcon.png"
}

for name in cash-register admin-console lister; do
  if [[ ! -f "$ICONS/${name}.png" ]]; then
    echo "Missing $ICONS/${name}.png" >&2
    exit 1
  fi
done

install_ios "$ICONS/cash-register.png" "$ROOT/ios-pos/CloudStorePos/Assets.xcassets/AppIcon.appiconset"
install_ios "$ICONS/admin-console.png" "$ROOT/ios-admin/CloudStoreAdmin/Assets.xcassets/AppIcon.appiconset"
install_ios "$ICONS/lister.png" "$ROOT/ios-lister/CloudStoreLister/Assets.xcassets/AppIcon.appiconset"

install_android "$ICONS/cash-register.png" "$ROOT/android-pos/app/src/main/res"
install_android "$ICONS/lister.png" "$ROOT/android-lister/app/src/main/res"

echo "Installed app icons:"
echo "  iOS POS, Admin, Lister"
echo "  Android POS, Lister"
