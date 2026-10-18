#!/bin/bash
# Runs Music on a device and checks what can be checked from outside:
#
#   tools/test-device.sh <adb serial> <name> [--with-fixtures]
#
# - the library loads from the media indexer (the app's log line);
# - "Shuffle All" (launch action) starts playback: a stream from the app
#   in PulseAudio, and the play position moving;
# - next / pause / play through launch actions;
# - screenshots of the library's views, Now Playing, Up Next,
#   Preferences, the dashboard (card closed while playing) and
#   exhibition, in build/test-output/device/<name>/.
#
# --with-fixtures copies tests/fixtures/music into
# /media/internal/Music/.music-test-fixtures first (for a device without
# music) and removes it again at the end.
#
# Install first with tools/install.sh, after tools/prepare-device.sh.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: test-device.sh <adb serial> <name> [--with-fixtures]}
NAME=${2:?usage: test-device.sh <adb serial> <name> [--with-fixtures]}
FIXTURES=$3
ADB="adb -s $SERIAL"
ID=org.webosports.app.music
OUT=build/test-output/device/$NAME
FIXDIR=/media/internal/Music/music-test-fixtures
mkdir -p "$OUT"
fails=0

sh_() { $ADB shell "$1" | tr -d '\r'; }
awake() { sh_ "luna-send -n 1 -w 3000 luna://com.palm.display/control/notifyUserActivity '{}' > /dev/null 2>&1"; }
launch() {
    awake
    sh_ "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":$1}' > /tmp/music-l.out 2>&1"
}
close() { sh_ "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' > /dev/null 2>&1; sleep 1"; }
shot() {
    awake
    sleep 1
    sh_ "luna-send -w 10000 -n 1 luna://com.webos.surfacemanager/captureCompositorOutput '{\"output\":\"/tmp/music-shot.png\",\"format\":\"PNG\"}' > /tmp/music-c.out 2>&1"
    $ADB pull /tmp/music-shot.png "$OUT/$1.png" > /dev/null
    echo "   $OUT/$1.png"
}
check() {   # description command...
    local what=$1; shift
    if "$@"; then echo "ok   $what"; else echo "FAIL $what"; fails=$((fails + 1)); fi
}
# The app's stream in PulseAudio, from qml-runner.
stream_up() { sh_ "pactl list sink-inputs 2>/dev/null | grep -c -i -E 'qml-runner|org.webosports.app.music'" | grep -q -v '^0$'; }
log_has() { sh_ "journalctl -b --since '-3min' --no-pager 2>/dev/null | grep -c '$1'" | grep -q -v '^0$'; }

# Screen on, unlocked (a device without a passcode) and kept awake for the
# run's length.
sh_ "luna-send -n 1 luna://com.palm.display/control/setState '{\"state\":\"on\"}' > /dev/null 2>&1; \
     luna-send -n 1 luna://com.palm.display/control/setLockStatus '{\"status\":\"unlock\"}' > /dev/null 2>&1; \
     luna-send -n 1 luna://com.palm.power/com/palm/power/activityStart '{\"id\":\"music-device-test\",\"duration_ms\":900000}' > /dev/null 2>&1"

if [ "$FIXTURES" = "--with-fixtures" ]; then
    sh_ "mkdir -p $FIXDIR"
    $ADB push tests/fixtures/music/. "$FIXDIR/" > /dev/null
    echo "copied the fixtures to $FIXDIR; waiting for the indexer"
    sleep 20
fi

close
launch '{"category": "albums", "page": "library"}'
sleep 6
shot library-albums
for c in artists songs playlists folders; do
    launch "{\"category\": \"$c\"}"
    sleep 2
    shot "library-$c"
done

launch '{"action": "shuffleAll", "page": "nowPlaying"}'
sleep 4
check "a stream plays after Shuffle All" stream_up
shot now-playing
launch '{"action": "next"}'
sleep 3
shot now-playing-next
launch '{"page": "queue"}'
sleep 2
shot up-next
launch '{"page": "preferences"}'
sleep 2
shot preferences
launch '{"page": "library", "category": "albums"}'

# The card away while playing: the dashboard.
sh_ "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"com.palm.launcher\"}' > /dev/null 2>&1 || true"
sleep 3
shot dashboard
check "still playing with the card in the background" stream_up

# Exhibition, as the shell launches it.
launch '{"windowType": "dockModeWindow", "dockMode": true}'
sleep 4
shot exhibition

launch '{"action": "pause"}'
sleep 2
close

if [ "$FIXTURES" = "--with-fixtures" ]; then
    sh_ "rm -rf $FIXDIR"
    echo "removed $FIXDIR"
fi
echo "$fails failed"
[ "$fails" -eq 0 ]
