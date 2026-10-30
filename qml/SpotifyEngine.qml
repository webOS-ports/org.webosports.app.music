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

/*
 * Spotify, which only plays through librespot: the music streaming
 * service runs it and drives it over Spotify Connect (/player/*). The same
 * face as Engine - load, play, pause, seek, the position and the end of a
 * track - so Player treats it as another decoder.
 *
 * The daemon reports where librespot is (/player/status, about a second
 * behind) but never that a track ended: the end is a track that was near
 * its end and stops, or is replaced by another. Between polls the position
 * runs on from the last report.
 *
 * Its report is Spotify's Web API, not librespot itself, and it lags: right
 * after a pause it can still say playing, and now and then it says paused
 * for one poll in the middle of a track. Taken as it came, the play state
 * bounced back for a second after a pause, and every bounce told the media
 * session playing had started again - which took the headset's keys from
 * whatever else was playing. So a report sent before the last command is
 * dropped, and a play state other than ours is only taken once
 * confirmPolls reports in a row agree on it.
 */
Item {
    id: engine

    property string baseUrl: "http://127.0.0.1:8730"
    // function(method, url, body, done(httpStatus, json)): StreamingStore's.
    property var transport: null

    readonly property string path: _path
    property real gainFactor: 1
    property real fadeFactor: 1
    property real masterFactor: 1
    // Spotify Connect has no speed.
    property real rate: 1
    // reports in a row that must agree before a different play state is taken
    property int confirmPolls: 2

    readonly property int playbackState: _playing ? MediaPlayer.PlayingState
                                                  : (_loaded ? MediaPlayer.PausedState : MediaPlayer.StoppedState)
    readonly property bool isPlaying: _playing
    readonly property bool loaded: _path !== ""
    readonly property real position: _position
    readonly property real duration: _duration
    readonly property bool seekable: _loaded
    readonly property string errorString: _error

    signal endOfMedia()
    signal failed(string reason)

    property string _path: ""
    property bool _loaded: false       // librespot has the track
    property bool _playing: false
    property real _position: 0
    property real _duration: 0
    property real _startAt: 0          // where play() starts an unloaded track
    property double _reportedAt: 0
    property real _reported: 0
    property bool _ended: false
    property string _error: ""
    property int _commands: 0          // bumped by every command sent
    property int _disagreed: 0         // reports in a row against _playing

    // Every command makes the reports asked for before it stale.
    function _command() {
        _commands++;
        _disagreed = 0;
    }

    function _call(method, endpoint, body, done) {
        if (!transport)
            return;
        transport(method, baseUrl + endpoint, body, function(code, data) {
            if (done)
                done(code, data);
        });
    }

    function load(p) {
        if (p === _path)
            return;
        _command();
        _path = p || "";
        _loaded = false;
        _playing = false;
        _position = 0;
        _duration = 0;
        _startAt = 0;
        _ended = false;
        _error = "";
    }

    function unload() {
        if (_loaded)
            _call("POST", "/player/pause", null, null);
        load("");
    }

    function play() {
        if (_path === "")
            return;
        _command();
        if (!_loaded) {
            _call("POST", "/player/load", { uri: _path, position_ms: Math.round(_startAt) }, function(code, data) {
                if (code !== 200) {
                    engine._error = (data && data.error) ? data.error : "Spotify is not ready.";
                    engine.failed(engine._error);
                    return;
                }
                engine._loaded = true;
                engine._playing = true;
                engine._reported = engine._startAt;
                engine._reportedAt = Date.now();
                if (data && data.duration_ms > 0)
                    engine._duration = data.duration_ms;
                engine._sendVolume();
            });
            return;
        }
        _call("POST", "/player/play", null, null);
        _playing = true;
        _reportedAt = Date.now();
        _reported = _position;
    }

    function pause() {
        _command();
        if (_loaded)
            _call("POST", "/player/pause", null, null);
        _playing = false;
    }

    function stop() {
        pause();
    }

    function seek(ms) {
        var to = Math.max(0, ms);
        if (!_loaded) {
            _startAt = to;
            _position = to;
            return;
        }
        _command();
        _call("POST", "/player/seek", { position_ms: Math.round(to) }, null);
        _position = to;
        _reported = to;
        _reportedAt = Date.now();
        _ended = false;
    }

    readonly property real _volume: Math.max(0, Math.min(1, gainFactor * fadeFactor * masterFactor))
    on_VolumeChanged: volumeTimer.restart()

    function _sendVolume() {
        if (_loaded)
            _call("POST", "/player/volume", { volume: Math.round(_volume * 100) }, null);
    }

    // A fade steps the volume twenty times a second; Connect gets the last.
    Timer {
        id: volumeTimer
        interval: 200
        onTriggered: engine._sendVolume()
    }

    // The position between reports.
    Timer {
        interval: 250
        repeat: true
        running: engine._playing
        onTriggered: {
            var at = engine._reported + (Date.now() - engine._reportedAt);
            engine._position = engine._duration > 0 ? Math.min(at, engine._duration) : at;
        }
    }

    // A report on the poll sent when _commands was `asked`.
    function _onStatus(code, s, asked) {
        if (code !== 200 || !s || !_loaded || asked !== _commands)
            return;
        var nearEnd = _duration > 0 && _position >= _duration - 3000;
        var ours = !s.uri || s.uri === _path;
        if (s.duration_ms > 0 && ours)
            _duration = s.duration_ms;
        // Stopped near the end, or moved on to something else: the end.
        if (!_ended && _playing && nearEnd && (!s.is_playing || !ours)) {
            _ended = true;
            _playing = false;
            endOfMedia();
            return;
        }
        if (!ours)
            return;
        var playing = !!s.is_playing;
        if (playing !== _playing && ++_disagreed < confirmPolls)
            return;
        _disagreed = 0;
        _playing = playing;
        _reported = s.position_ms || 0;
        _reportedAt = Date.now();
        _position = _reported;
    }

    function _poll() {
        var asked = _commands;
        _call("GET", "/player/status", null, function(code, s) { engine._onStatus(code, s, asked); });
    }

    Timer {
        interval: 1000
        repeat: true
        running: engine._loaded
        onTriggered: engine._poll()
    }
}
