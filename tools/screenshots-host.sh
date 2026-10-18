#!/bin/sh
# Screenshots of every screen as each device shows it - its screen size
# and grid unit - from luneos-components' desktop stand-ins, on the build
# host. One contact sheet per device in build/test-output/screens/.
#
#   tools/screenshots-host.sh <host build dir> [luneos-components] [profile...]
#
# The host build is this project built for the host with -DBUILD_TESTING=ON
# (it holds the plugin and musicapp-screens). Profiles are the stand-ins'
# (test/imports/LunaNext/Common/SettingsStub.js): mindphone, q25, tp, n7...
set -e
cd "$(dirname "$0")/.."
SRC=$(pwd)
BUILD=$(cd "${1:?usage: screenshots-host.sh <host build dir> [luneos-components] [profile...]}" && pwd)
LC=$(cd "${2:-../luneos-components}" && pwd)
shift; [ $# -gt 0 ] && shift
PROFILES=${*:-mindphone q25 tp n7}
OUT=$SRC/build/test-output/screens
mkdir -p "$OUT"
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT
for p in $PROFILES; do
    rm -rf "$CONF"/*
    XDG_CONFIG_HOME=$CONF XDG_DATA_HOME=$CONF/data XDG_CACHE_HOME=$CONF/cache MUSIC_ART_CACHE=$CONF/art \
    QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        "$BUILD/tests/musicapp-screens" -I "$BUILD" -I "$LC/modules" -I "$LC/test/imports" \
        --out "$OUT" --profile="$p" "$SRC/tests/screens/screens.qml" > "$OUT/$p.log" 2>&1 || { echo "$p: FAILED (see $OUT/$p.log)"; continue; }
    if command -v magick > /dev/null; then
        magick montage "$OUT/$p"-*.png -tile 5x -geometry +4+4 -resize 50% -background '#666' "$OUT/sheet-$p.png"
    fi
    echo "$p: $(ls "$OUT/$p"-*.png | wc -l) screens, $OUT/sheet-$p.png"
done
