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
 * One decoder: a MediaPlayer and its output, with the three things that
 * scale its volume kept apart - the track's ReplayGain, a crossfade or
 * sleep fade, and the user's master level - so each can change on its own.
 * Player keeps two, one playing and one with the next track loaded.
 */
Item {
    id: engine

    // The file loaded, "" for none.
    readonly property string path: _path
    property real gainFactor: 1
    property real fadeFactor: 1
    property real masterFactor: 1
    property real rate: 1

    readonly property alias playbackState: media.playbackState
    readonly property alias mediaStatus: media.mediaStatus
    readonly property alias position: media.position
    readonly property alias duration: media.duration
    readonly property alias seekable: media.seekable
    readonly property alias errorString: media.errorString
    readonly property alias source: media.source
    readonly property bool isPlaying: media.playbackState === MediaPlayer.PlayingState
    readonly property bool loaded: media.mediaStatus === MediaPlayer.LoadedMedia
                                   || media.mediaStatus === MediaPlayer.BufferedMedia
                                   || media.mediaStatus === MediaPlayer.BufferingMedia

    signal endOfMedia()
    signal failed(string reason)

    property string _path: ""

    // A path as a file:// URL: "#" and "?" in a file name would otherwise
    // be read as the URL's fragment and query.
    function urlFor(p) {
        return "file://" + p.split("/").map(encodeURIComponent).join("/");
    }

    // url: what plays it, when that is not the file at p (a streamed
    // track's resolved URL).
    function load(p, url) {
        if (p === _path && media.source.toString() !== "")
            return;
        _path = p || "";
        media.source = _path ? (url ? url : urlFor(_path)) : "";
    }

    function unload() {
        media.stop();
        _path = "";
        media.source = "";
    }

    function play() { media.play(); }
    function pause() { media.pause(); }
    function stop() { media.stop(); }
    function seek(ms) { media.setPosition(Math.max(0, ms)); }

    MediaPlayer {
        id: media
        playbackRate: engine.rate
        audioOutput: AudioOutput {
            volume: Math.max(0, Math.min(1, engine.gainFactor * engine.fadeFactor * engine.masterFactor))
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia)
                engine.endOfMedia();
            else if (mediaStatus === MediaPlayer.InvalidMedia && engine._path !== "")
                engine.failed(errorString !== "" ? errorString : "This file cannot be played.");
        }
        onErrorOccurred: function(error, errorString) {
            if (engine._path !== "")
                engine.failed(errorString !== "" ? errorString : "This file cannot be played.");
        }
    }
}
