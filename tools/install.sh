#!/bin/bash
# Packs the app with a device build of its plugin into an ipk and installs
# it through com.webos.appInstallService, as Preware does: opkg with its own
# root (/media/cryptofs/apps), so system packages are left alone, and the
# app's bus permissions come from requiredPermissions in appinfo.json.
# For development; the recipe does the real install.
#
#   tools/install.sh <build dir> <adb serial>
#
# Build the plugin for the device's architecture first (README.md). The
# package says "Architecture: all" although it holds the plugin: the
# installer's opkg (/etc/palm/appinstalld/opkg.conf) takes nothing else.
set -e
cd "$(dirname "$0")/.."
BUILD=${1:?usage: tools/install.sh <build dir> <adb serial>}
SERIAL=${2:?usage: tools/install.sh <build dir> <adb serial>}
ADB="adb -s $SERIAL"

ID=$(python3 -I -c 'import json; print(json.load(open("appinfo.json"))["id"])')
VERSION=$(python3 -I -c 'import json; print(json.load(open("appinfo.json"))["version"])')
PLUGIN=$BUILD/MusicApp/libmusicapp-qml.so
[ -f "$PLUGIN" ] || { echo "no plugin at $PLUGIN"; exit 1; }

WORK=$BUILD/ipk
rm -rf "$WORK"
APP=$WORK/data/usr/palm/applications/$ID
mkdir -p "$WORK/control" "$APP/MusicApp"
cp -r appinfo.json icon.png icon-256x256.png qml "$APP/"
cp "$PLUGIN" MusicApp/qmldir "$APP/MusicApp/"

cat > "$WORK/control/control" <<CONTROL
Package: $ID
Version: $VERSION
Section: misc
Priority: optional
Architecture: all
Installed-Size: $(du -sk "$WORK/data" | cut -f1)
Maintainer: Herman van Hazendonk <github.com@herrie.org>
Description: Music
 The songs on the device by album, artist, genre, folder and playlist.
webOS-Package-Format-Version: 2
webOS-Packager-Version: x.y.x
CONTROL

echo "2.0" > "$WORK/debian-binary"
TAROPTS="--owner=0 --group=0 --numeric-owner --sort=name"
tar $TAROPTS -czf "$WORK/control.tar.gz" -C "$WORK/control" ./control
tar $TAROPTS -czf "$WORK/data.tar.gz" -C "$WORK/data" ./usr
IPK=${ID}_${VERSION}_all.ipk
rm -f "$BUILD/$IPK"
(cd "$WORK" && ar rc "../$IPK" debian-binary control.tar.gz data.tar.gz)

$ADB push "$BUILD/$IPK" /tmp/ >/dev/null
# luna-send prints nothing on an adb pipe; results go through a file.
$ADB shell "luna-send -w 90000 -i luna://com.webos.appInstallService/install '{\"id\":\"$ID\",\"ipkUrl\":\"/tmp/$IPK\",\"subscribe\":true}' > /tmp/music-inst.out 2>&1 & P=\$!; \
    for i in \$(seq 1 60); do sleep 1; grep -qE '\"installed\"|failed|errorCode' /tmp/music-inst.out && break; done; kill \$P 2>/dev/null; \
    rm -f /tmp/$IPK; grep -oE '\"state\":\"installed\"|errorText\":\"[^\"]*\"' /tmp/music-inst.out | tail -n 1"

# The installer writes the app's bus permissions to /var/luna-service2 but
# the hub does not pick them up by itself: until it rescans, every call the
# app makes is denied - SAM's registerApp too, so SAM closes the app right
# after each launch.
# The installer reports "installed" before it has written those files, so
# wait for them, then rescan.
$ADB shell "for i in \$(seq 1 20); do [ -f /var/luna-service2/client-permissions.d/$ID.app.json ] && break; sleep 1; done; \
    sleep 2; ls-control scan-volatile-dirs > /dev/null 2>&1; true"
