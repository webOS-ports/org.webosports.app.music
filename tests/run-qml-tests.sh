#!/bin/sh
# Runs the QML tests on the build host: the queue, the library and the
# lyrics (tst_queue, tst_library) and the app itself (tst_ui) with
# luneos-components' desktop stand-ins and the MusicApp plugin built for
# the host.
#
#   tests/run-qml-tests.sh <plugin build dir> [path to luneos-components [qmltestrunner arguments]]
#
# The plugin build dir is a host build of this project (it holds
# MusicApp/qmldir and the plugin). luneos-components needs its desktop
# build (CONFIG+=desktop) for the style and LuneOS.Components plugins, and
# a checkout with ActionSheet and FastScroller. Screenshots of every
# screen at every size land in build/test-output/test-screens.
set -e
cd "$(dirname "$0")/.."
SRC=$(pwd)
BUILD=$(cd "${1:?usage: run-qml-tests.sh <plugin build dir> [luneos-components]}" && pwd)
[ $# -gt 0 ] && shift
LC=$(cd "${1:-../luneos-components}" && pwd)
[ $# -gt 0 ] && shift
OUT=$SRC/build/test-output
mkdir -p "$OUT/test-screens"
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT
cd "$OUT"
# Preferences, the queue, the tag cache and the covers go to a throwaway
# directory, not the user's.
XDG_CONFIG_HOME=$CONF XDG_DATA_HOME=$CONF/data XDG_CACHE_HOME=$CONF/cache MUSIC_ART_CACHE=$CONF/art \
QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
    ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -import "$BUILD" -import "$LC/modules" -import "$LC/test/imports" \
    -input "$SRC/tests/qml" "$@"
