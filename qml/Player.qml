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

import "js/Queue.js" as Queue
import "js/Streaming.js" as Streaming

/*
 * Plays the queue.
 *
 * Two engines take turns: while one plays, the next track is loaded in the
 * other, so when a track ends the next starts from a decoder that is
 * already prerolled - as near to gapless as Qt Multimedia gets - or, with a
 * crossfade set, starts that many seconds early while the two volumes
 * cross.
 *
 * The queue itself is plain data (js/Queue.js); every change goes through
 * _set() so the views see it.
 */
Item {
    id: player

    // --- the queue, for the views ----------------------------------------
    property var queue: Queue.create()
    readonly property var current: Queue.current(queue)
    readonly property int currentPos: queue.pos
    readonly property int count: queue.items.length
    readonly property bool hasQueue: count > 0
    readonly property bool shuffle: queue.shuffle
    readonly property string repeat: queue.repeat
    readonly property bool hasNext: Queue.nextPos(queue, false) >= 0

    // --- playback state ----------------------------------------------------
    readonly property bool playing: active.isPlaying
    readonly property real position: _seekingTo >= 0 ? _seekingTo : active.position
    readonly property real duration: active.duration > 0 ? active.duration : (current ? (current.duration || 0) : 0)
    readonly property bool seekable: active.seekable

    // --- settings (main.qml binds these to the preferences) --------------
    property real rate: 1.0
    // "off", "track", "album", or "auto": album gain while an album plays
    // in order, track gain otherwise.
    property string replayGain: "auto"
    property bool preventClipping: true
    // Overlap between tracks in ms; 0 is gapless.
    property int crossfadeMs: 0
    // Lowered by the sleep timer as it runs out.
    property real sleepFade: 1.0
    // function(path) -> { trackGain, albumGain, trackPeak, albumPeak } or
    // null: the library's tag data, read lazily by TagReader.
    property var gainLookup: null
    // function(track) -> ms to resume a long track at, or 0.
    property var resumeLookup: null
    // function(track, done(url, error)): what plays a streamed track
    // (StreamingStore.resolve). Files play from their path.
    property var urlResolver: null
    // The HTTP calls of the music streaming service, for Spotify.
    property var streamingTransport: null

    // --- what happened ------------------------------------------------------
    // A track began to play.
    signal started(var track)
    // A track stopped being the current one: how long it actually played
    // and whether it reached its end. For play counts.
    signal finished(var track, real playedMs, bool completed)
    // Where a long track is, every 15 s while it plays and when it pauses.
    signal bookmark(var track, real positionMs)
    // A track could not be played and was skipped.
    signal failed(var track, string reason)
    // The queue ran out.
    signal ended()

    // --- internals ------------------------------------------------------------
    property int _activeIndex: 0
    // Spotify's tracks play through librespot, not either engine.
    property bool _spotifyActive: false
    readonly property var active: _spotifyActive ? spotifyEngine : (_activeIndex === 0 ? engineA : engineB)
    readonly property Engine standby: _activeIndex === 0 ? engineB : engineA
    // Bumped for every track started, so a resolve that answers late for a
    // track no longer current is dropped.
    property int _startSerial: 0
    // The queue position the standby engine has loaded, -1 for none.
    property int _preloadedPos: -1
    property string _preloadedPath: ""
    // While a crossfade runs, the engine fading out.
    property Engine _fadingOut: null
    property real _seekingTo: -1
    property real _playedMs: 0
    property double _lastTick: 0
    property bool _completed: false
    property int _failures: 0
    property string _failedPath: ""
    // A start asked for before the track was loaded (seek to resume point).
    property real _pendingSeek: -1
    property bool _wantPlay: false

    Engine {
        id: engineA
        objectName: "engineA"
        rate: player.rate
        masterFactor: player.sleepFade
        onEndOfMedia: player._onEnd(engineA)
        onFailed: function(reason) { player._onFailed(engineA, reason); }
    }
    SpotifyEngine {
        id: spotifyEngine
        objectName: "spotifyEngine"
        transport: player.streamingTransport
        masterFactor: player.sleepFade
        onEndOfMedia: player._onEnd(spotifyEngine)
        onFailed: function(reason) { player._onFailed(spotifyEngine, reason); }
    }
    Engine {
        id: engineB
        objectName: "engineB"
        rate: player.rate
        masterFactor: player.sleepFade
        onEndOfMedia: player._onEnd(engineB)
        onFailed: function(reason) { player._onFailed(engineB, reason); }
    }

    function _set(state) {
        // A copy: the Queue functions change the object they are given, and
        // assigning the same object again would not notify the bindings.
        queue = Object.assign({}, state);
    }

    // --- playing ----------------------------------------------------------------

    /* Replaces the queue with tracks and plays tracks[start] (shuffle: -1
     * picks a random first one). */
    function playTracks(tracks, start, shuffleOn) {
        if (!tracks || tracks.length === 0)
            return;
        _finishCurrent(false);
        var state = Queue.setTracks(Queue.create(), tracks, start, !!shuffleOn);
        state.repeat = queue.repeat;
        _set(state);
        _failures = 0;
        // Picked again after it failed (a stream that did not resolve the
        // first time): a real attempt, not the remembered failure.
        _failedPath = "";
        _startCurrent(true, 0);
    }

    function play() {
        if (!current)
            return;
        if (active.path !== current.path) {
            _failedPath = "";
            _startCurrent(true, _pendingSeek > 0 ? _pendingSeek : 0);
            return;
        }
        _wantPlay = true;
        _lastTick = Date.now();
        active.play();
    }

    function pause() {
        _wantPlay = false;
        active.pause();
        if (_fadingOut)
            _endFade();
        _saveBookmark();
    }

    function toggle() {
        if (playing)
            pause();
        else
            play();
    }

    function stop() {
        pause();
        active.seek(0);
    }

    function next() {
        var pos = Queue.nextPos(queue, false);
        if (pos < 0)
            return;
        _goTo(pos, false);
    }

    /* Back to the start of the track after the first few seconds, as every
     * player does; to the one before within them. */
    function previous() {
        if (position > 3000 || Queue.previousPos(queue) === queue.pos) {
            seek(0);
            return;
        }
        _goTo(Queue.previousPos(queue), false);
    }

    function jumpTo(pos) {
        if (pos < 0 || pos >= count)
            return;
        _failedPath = "";
        _goTo(pos, false);
    }

    function seek(ms) {
        if (!current)
            return;
        var target = Math.max(0, Math.min(ms, duration > 0 ? duration - 250 : ms));
        if (active.path !== current.path) {
            _pendingSeek = target;
            return;
        }
        _seekingTo = target;
        seekSettle.restart();
        active.seek(target);
    }

    function setShuffle(on) {
        _set(Queue.setShuffle(queue, on));
        _dropPreload();
    }

    function setRepeat(mode) {
        _set(Queue.setRepeat(queue, mode));
        _dropPreload();
    }

    function cycleRepeat() {
        setRepeat(Queue.nextRepeatMode(queue.repeat));
    }

    // --- the queue ------------------------------------------------------------------

    function playNext(tracks) {
        var wasEmpty = !hasQueue;
        _set(Queue.playNext(queue, tracks));
        _dropPreload();
        if (wasEmpty)
            _startCurrent(true, 0);
    }

    function enqueue(tracks) {
        var wasEmpty = !hasQueue;
        _set(Queue.enqueue(queue, tracks));
        _dropPreload();
        if (wasEmpty)
            _startCurrent(true, 0);
    }

    function moveItem(from, to) {
        _set(Queue.move(queue, from, to));
        _dropPreload();
    }

    function removeItem(pos) {
        var removingCurrent = pos === queue.pos;
        var wasPlaying = playing;
        if (removingCurrent)
            _finishCurrent(false);
        _set(Queue.removeAt(queue, pos));
        _dropPreload();
        if (removingCurrent) {
            if (current)
                _startCurrent(wasPlaying, 0);
            else
                _stopAll();
        }
    }

    function clearQueue() {
        _finishCurrent(false);
        _set(Queue.clear(queue));
        _stopAll();
    }

    function clearUpcoming() {
        _set(Queue.clearUpcoming(queue));
        _dropPreload();
    }

    /* The queue from a saved state (Queue.deserialize), paused at its
     * position: restoring must never start the music by itself. */
    function restore(state) {
        if (!state || state.items.length === 0)
            return;
        _set(state);
        _pendingSeek = state.position || 0;
        _wantPlay = false;
        // A streamed track is resolved when it is played, not now.
        if (!Streaming.isRemote(current.path)) {
            active.load(current.path);
            _applyGain(active, current);
        }
    }

    // --- internals ----------------------------------------------------------------------

    function _goTo(pos, auto) {
        var wasPlaying = playing || _wantPlay;
        _finishCurrent(_completed);
        _set(Queue.jump(queue, pos));
        _startCurrent(wasPlaying || auto, 0);
    }

    function _stopAll() {
        _wantPlay = false;
        engineA.unload();
        engineB.unload();
        spotifyEngine.unload();
        _spotifyActive = false;
        _preloadedPos = -1;
        _preloadedPath = "";
        _fadingOut = null;
        fadeTimer.stop();
    }

    function _dropPreload() {
        if (_preloadedPos < 0)
            return;
        _preloadedPos = -1;
        _preloadedPath = "";
        if (standby !== _fadingOut)
            standby.unload();
    }

    /* Starts queue.pos on the active engine - or, when the standby engine
     * already has it loaded, swaps to that one. */
    function _startCurrent(andPlay, at) {
        var track = current;
        if (!track) {
            _stopAll();
            return;
        }
        if (_fadingOut)
            _endFade();
        var serial = ++_startSerial;
        var resolving = false;
        if (Streaming.isSpotify(track.path)) {
            engineA.unload();
            engineB.unload();
            _spotifyActive = true;
            spotifyEngine.load(track.path);
        } else {
            if (_spotifyActive) {
                spotifyEngine.unload();
                _spotifyActive = false;
            }
            if (_preloadedPos === queue.pos && _preloadedPath === track.path) {
                active.stop();
                active.unload();
                _activeIndex = 1 - _activeIndex;
            } else {
                standby.unload();
                active.stop();
                if (Streaming.isRemote(track.path)) {
                    active.unload();
                    resolving = true;
                } else {
                    active.load(track.path);
                }
            }
        }
        _preloadedPos = -1;
        _preloadedPath = "";
        _applyGain(active, track);
        active.fadeFactor = 1;
        _playedMs = 0;
        _completed = false;
        _lastTick = Date.now();

        var resumeAt = at > 0 ? at : 0;
        if (resumeAt === 0 && resumeLookup)
            resumeAt = resumeLookup(track) || 0;
        _pendingSeek = resumeAt > 0 ? resumeAt : -1;
        _wantPlay = andPlay;
        if (resolving) {
            _resolveAndLoad(track, serial);
        } else {
            if (_pendingSeek > 0 && active.seekable) {
                active.seek(_pendingSeek);
                _pendingSeek = -1;
            }
            if (_spotifyActive && _pendingSeek > 0) {
                active.seek(_pendingSeek);
                _pendingSeek = -1;
            }
            if (andPlay)
                active.play();
        }
        started(track);
    }

    // A streamed track: its URL from the streaming service, then as a file.
    function _resolveAndLoad(track, serial) {
        if (!urlResolver) {
            _onFailed(active, "Streaming is not available.");
            return;
        }
        urlResolver(track, function(url, error) {
            if (serial !== player._startSerial)
                return;
            if (!url) {
                player._onFailed(player.active, error || "The track cannot be streamed.");
                return;
            }
            player.active.load(track.path, url);
            if (player._wantPlay)
                player.active.play();
        });
    }

    function _finishCurrent(completed) {
        var track = current;
        if (!track)
            return;
        _tick();
        if (_playedMs > 0 || completed)
            finished(track, _playedMs, completed);
        _saveBookmark();
        _playedMs = 0;
        _completed = false;
    }

    function _saveBookmark() {
        if (current && active.path === current.path && position > 0)
            bookmark(current, position);
    }

    function _onEnd(engine) {
        if (engine === _fadingOut) {
            _endFade();
            return;
        }
        if (engine !== active)
            return;
        _completed = true;
        _failures = 0;
        var pos = Queue.nextPos(queue, true);
        if (pos < 0) {
            _finishCurrent(true);
            _wantPlay = false;
            // Back to the start of the queue, paused, as every player ends.
            _set(Queue.jump(queue, 0));
            if (current) {
                active.load(current.path);
                _applyGain(active, current);
                active.seek(0);
            }
            ended();
            return;
        }
        if (pos === queue.pos) {
            // Repeat one.
            _finishCurrent(true);
            _playedMs = 0;
            active.seek(0);
            active.play();
            started(current);
            return;
        }
        _goTo(pos, true);
    }

    function _onFailed(engine, reason) {
        if (engine !== active) {
            // The preloaded next track will not play; find out when it is due.
            if (engine === standby && _preloadedPos >= 0) {
                _preloadedPos = -1;
                _preloadedPath = "";
            }
            return;
        }
        var track = current;
        if (!track || _failedPath === track.path)
            return;
        _failedPath = track.path;
        failed(track, reason);
        _failures++;
        var pos = Queue.nextPos(queue, false);
        // Three in a row is not a bad file but a broken setup (no decoder
        // for the format): stop rather than race through the queue.
        if (_failures >= 3 || pos < 0 || pos === queue.pos) {
            _wantPlay = false;
            return;
        }
        _set(Queue.jump(queue, pos));
        _startCurrent(true, 0);
    }

    function _gainFor(track) {
        if (replayGain === "off" || !track)
            return 1;
        var tags = gainLookup ? gainLookup(track.path) : null;
        tags = tags || track;
        var useAlbum = replayGain === "album";
        if (replayGain === "auto" && !queue.shuffle) {
            // Neighbours in the queue from the same album: an album is
            // playing in order, and its quiet tracks should stay quiet.
            var items = queue.items, p = queue.pos;
            var prev = p > 0 ? items[p - 1] : null;
            var nxt = p + 1 < items.length ? items[p + 1] : null;
            useAlbum = (prev && prev.album === track.album && prev.albumArtist === track.albumArtist)
                    || (nxt && nxt.album === track.album && nxt.albumArtist === track.albumArtist);
        }
        var gain = useAlbum && tags.albumGain !== undefined ? tags.albumGain : tags.trackGain;
        var peak = useAlbum && tags.albumPeak !== undefined ? tags.albumPeak : tags.trackPeak;
        if (gain === undefined || gain === null || isNaN(gain))
            return 1;
        var factor = Math.pow(10, gain / 20);
        if (preventClipping && peak > 0 && factor * peak > 1)
            factor = 1 / peak;
        return Math.min(1, factor);
    }

    function _applyGain(engine, track) {
        engine.gainFactor = _gainFor(track);
    }

    function _tick() {
        var now = Date.now();
        if (playing && _lastTick > 0)
            _playedMs += Math.min(now - _lastTick, 5000);
        _lastTick = now;
    }

    function _preloadNext() {
        var pos = Queue.nextPos(queue, true);
        if (pos < 0 || pos === queue.pos || _fadingOut) {
            return;
        }
        var track = queue.items[pos];
        if (_preloadedPos === pos && _preloadedPath === track.path)
            return;
        // Spotify plays through librespot: nothing to load ahead, and no
        // crossfade into or out of it.
        if (_spotifyActive || Streaming.isSpotify(track.path))
            return;
        _preloadedPos = pos;
        _preloadedPath = track.path;
        standby.fadeFactor = crossfadeMs > 0 ? 0 : 1;
        if (!Streaming.isRemote(track.path)) {
            standby.load(track.path);
            return;
        }
        if (!urlResolver)
            return;
        var engine = standby;
        urlResolver(track, function(url, error) {
            // Still the one planned next, on the same engine?
            if (player._preloadedPos !== pos || player._preloadedPath !== track.path || player.standby !== engine)
                return;
            if (url)
                engine.load(track.path, url);
            else
                player._preloadedPos = -1;
        });
    }

    function _startCrossfade() {
        var pos = _preloadedPos;
        if (pos < 0 || !standby.loaded || _fadingOut || _spotifyActive)
            return;
        _completed = true;
        _finishCurrent(true);
        _fadingOut = active;
        _activeIndex = 1 - _activeIndex;
        _set(Queue.jump(queue, pos));
        _preloadedPos = -1;
        _preloadedPath = "";
        _applyGain(active, current);
        active.fadeFactor = 0;
        active.play();
        _playedMs = 0;
        _lastTick = Date.now();
        fadeTimer.startedAt = Date.now();
        fadeTimer.start();
        started(current);
    }

    function _endFade() {
        fadeTimer.stop();
        if (_fadingOut) {
            var old = _fadingOut;
            _fadingOut = null;
            old.unload();
            old.fadeFactor = 1;
        }
        active.fadeFactor = 1;
    }

    // Steps the crossfade's two volumes.
    Timer {
        id: fadeTimer
        property double startedAt: 0
        interval: 50
        repeat: true
        onTriggered: {
            var t = player.crossfadeMs > 0 ? (Date.now() - startedAt) / player.crossfadeMs : 1;
            if (t >= 1) {
                player._endFade();
                return;
            }
            player.active.fadeFactor = t;
            if (player._fadingOut)
                player._fadingOut.fadeFactor = 1 - t;
        }
    }

    // Once a second while playing: count the time played, load the next
    // track in time, start a crossfade, finish a seek and resume a start
    // that had to wait for the file to load.
    Timer {
        interval: 500
        repeat: true
        running: player.hasQueue
        onTriggered: {
            player._tick();
            var e = player.active;
            if (player._pendingSeek > 0 && e.seekable && e.path === (player.current ? player.current.path : "")) {
                e.seek(player._pendingSeek);
                player._pendingSeek = -1;
            }
            if (!player.playing)
                return;
            var left = player.duration - e.position;
            var lead = Math.max(15000, player.crossfadeMs + 5000);
            if (player.duration > 0 && left < lead)
                player._preloadNext();
            if (player.crossfadeMs > 0 && player.duration > player.crossfadeMs * 2
                    && left <= player.crossfadeMs && left > 0)
                player._startCrossfade();
        }
    }

    // Long tracks remember where they are.
    Timer {
        interval: 15000
        repeat: true
        running: player.playing
        onTriggered: player._saveBookmark()
    }

    // Until the engine reports the new position, show where the user let go.
    Timer {
        id: seekSettle
        interval: 600
        onTriggered: player._seekingTo = -1
    }

    // Paused from outside - the sound system gave the speaker to a call or
    // an alarm - is a pause: the play button must show it.
    Connections {
        target: player.active
        function onPlaybackStateChanged() {
            if (player.active.playbackState === MediaPlayer.PlayingState) {
                player._failures = 0;
                player._failedPath = "";
                player._lastTick = Date.now();
            }
        }
        function onSeekableChanged() {
            if (player.active.seekable && player._pendingSeek > 0) {
                player.active.seek(player._pendingSeek);
                player._pendingSeek = -1;
            }
        }
    }
}
