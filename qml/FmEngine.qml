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
import QtMultimedia

import "js/FmRadio.js" as Fm

/*
 * An FM station ("fm:<kHz>"), with the same face as Engine so Player
 * treats it as another decoder. Playing is the radio on at the station,
 * pausing is the radio off: the service plays it through PulseAudio as a
 * stream of its own, so there are no samples here, no position and no end.
 *
 * Its volume is the system's, as any stream on the FM sink: the factors
 * Player sets (ReplayGain, crossfade, the sleep timer's fade) do not reach
 * it. The sleep timer still ends it, with a pause.
 */
Item {
    id: engine

    // An FmRadio.
    property var radio: null

    readonly property string path: _path
    property real gainFactor: 1
    property real fadeFactor: 1
    property real masterFactor: 1
    property real rate: 1

    readonly property bool isPlaying: _on
    readonly property int playbackState: _on ? MediaPlayer.PlayingState
                                             : (_path !== "" ? MediaPlayer.PausedState : MediaPlayer.StoppedState)
    readonly property bool loaded: _path !== ""
    readonly property real position: 0
    readonly property real duration: 0
    readonly property bool seekable: false
    readonly property string errorString: _error

    signal endOfMedia()
    signal failed(string reason)

    property string _path: ""
    property int _khz: 0
    // What was asked for last, and what the radio does.
    property bool _want: false
    property bool _on: false
    // Bumped by every play and pause, so an answer to an older one is dropped.
    property int _serial: 0
    property string _error: ""

    function load(p) {
        if (p === _path)
            return;
        _path = p || "";
        _khz = Fm.khzOf(_path);
        _error = "";
        // Another station while one plays: the radio stays on and tunes.
        if (_want && _khz > 0)
            _start();
    }

    function unload() {
        pause();
        _path = "";
        _khz = 0;
    }

    function play() {
        if (_khz <= 0)
            return;
        _want = true;
        _start();
    }

    function _start() {
        if (!radio) {
            _fail("There is no FM radio.");
            return;
        }
        const serial = ++_serial;
        radio.powerOn(_khz, function(ok) {
            if (serial !== engine._serial)
                return;
            if (!ok) {
                engine._fail(radio.errorText !== "" ? radio.errorText : "The FM radio could not be switched on.");
                return;
            }
            engine._on = true;
        });
    }

    function _fail(reason) {
        _want = false;
        _on = false;
        _error = reason;
        failed(reason);
    }

    function pause() {
        const was = _want || _on;
        _want = false;
        _on = false;
        ++_serial;
        if (was && radio)
            radio.powerOff(null);
    }

    function stop() { pause(); }
    function seek(ms) { }

    // Switched off elsewhere - another app, the service restarting.
    Connections {
        target: engine.radio
        function onPoweredChanged() {
            if (!engine.radio.powered && engine._on) {
                engine._on = false;
                engine._want = false;
            }
        }
    }
}
