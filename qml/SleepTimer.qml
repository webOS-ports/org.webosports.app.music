/*
 * (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick

/*
 * Stops the music after a while, or at the end of the playing track. The
 * last half minute fades out, so the music does not cut off mid-note.
 */
Item {
    id: timer

    property var player

    readonly property bool running: _endAt > 0 || endOfTrack
    // Stop when the playing track ends instead of at a time.
    property bool endOfTrack: false
    readonly property real remainingMs: _endAt > 0 ? Math.max(0, _endAt - _now) : 0
    readonly property string remainingText: endOfTrack ? "end"
                                            : Math.ceil(remainingMs / 60000) + " min"

    property double _endAt: 0
    property double _now: Date.now()
    readonly property int fadeMs: 30000

    signal expired()

    function start(minutes) {
        endOfTrack = false;
        _now = Date.now();
        _endAt = _now + minutes * 60000;
    }

    function stopAtEndOfTrack() {
        _endAt = 0;
        endOfTrack = true;
    }

    function cancel() {
        _endAt = 0;
        endOfTrack = false;
        player.sleepFade = 1;
    }

    function _fire() {
        player.pause();
        cancel();
        expired();
    }

    Timer {
        interval: 1000
        repeat: true
        running: timer._endAt > 0
        onTriggered: {
            timer._now = Date.now();
            var left = timer._endAt - timer._now;
            if (left <= 0) {
                timer._fire();
                return;
            }
            timer.player.sleepFade = left < timer.fadeMs ? Math.max(0.05, left / timer.fadeMs) : 1;
        }
    }

    Connections {
        target: timer.player
        function onFinished(track, playedMs, completed) {
            if (timer.endOfTrack && completed)
                timer._fire();
        }
    }
}
