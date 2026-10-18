#!/bin/bash
# Gets a device ready for a development build of Music, ahead of the
# recipes that will do it for real:
#
# - luneos-components' ActionSheet, FastScroller and ConfirmDialog
#   (branch herrie/music-shared-parts) into the device's LuneOS.Components;
# - the media indexer's read grant for the app on com.palm.media.audio.file
#   (mediaindexer branch herrie/music-read-grant), applied by the
#   configurator, so the app reads the library without the permission
#   alert.
#
# The files it replaces are kept in /media/internal/.music-dev-backup on the
# device; tools/prepare-device.sh <serial> --restore puts them back.
#
#   tools/prepare-device.sh <adb serial> <luneos-components checkout> <mediaindexer checkout> [--restore]
set -e
SERIAL=${1:?usage: prepare-device.sh <serial> <luneos-components> <mediaindexer> [--restore]}
LC=${2:?}
MI=${3:?}
ADB="adb -s $SERIAL"
sh_() { $ADB shell "$1" | tr -d '\r'; }
COMP=$(sh_ 'dirname $(find /usr/lib -path "*LuneOS/Components/qmldir" | head -n 1)')
PERM=/etc/palm/db/permissions/com.palm.media.audio.file
BACKUP=/media/internal/.music-dev-backup
[ -n "$COMP" ] || { echo "no LuneOS.Components on the device"; exit 1; }

if [ "$4" = "--restore" ]; then
    sh_ "mount -o remount,rw / 2>/dev/null; cp $BACKUP/qmldir $BACKUP/ConfirmDialog.qml $COMP/ && rm -f $COMP/ActionSheet.qml $COMP/FastScroller.qml && cp $BACKUP/com.palm.media.audio.file $PERM && luna-send -n 1 -w 20000 luna://com.palm.configurator/run '{\"types\":[\"dbpermissions\"]}' > /dev/null 2>&1; echo restored"
    exit 0
fi

# Only onto the luneos-components these files were made against: every
# file the new qmldir names must be on the device already or pushed here.
# An older image (the TouchPad's 64a8550 has no js/AppFiles.js) would lose
# LuneOS.Components for every app.
missing=""
for f in $(awk 'NF >= 3 { print $3 }' "$LC/modules/LuneOS/Components/qmldir"); do
    case $f in ActionSheet.qml|FastScroller.qml) continue ;; esac
    [ "$(sh_ "[ -f $COMP/$f ] && echo yes")" = yes ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "the device's LuneOS.Components is older than this checkout (no$missing): update luneos-components there first"
    exit 1
fi

sh_ "mkdir -p $BACKUP; [ -f $BACKUP/qmldir ] || cp $COMP/qmldir $COMP/ConfirmDialog.qml $PERM $BACKUP/"
sh_ "mount -o remount,rw / 2>/dev/null; true"
for f in ActionSheet.qml FastScroller.qml ConfirmDialog.qml qmldir; do
    $ADB push "$LC/modules/LuneOS/Components/$f" "$COMP/$f" > /dev/null
done
$ADB push "$MI/files/db8/permissions/com.palm.media.audio.file" "$PERM" > /dev/null
# The configurator processes changed files only; its stamp for this one goes.
sh_ "rm -f /var/cache/configurator/_etc_palm_db_permissions_com.palm.media.audio.file; luna-send -n 1 -w 20000 luna://com.palm.configurator/run '{\"types\":[\"dbpermissions\"]}' > /tmp/music-conf.out 2>&1; cat /tmp/music-conf.out"
echo "LuneOS.Components in $COMP updated; read grant applied (backups in $BACKUP)"
