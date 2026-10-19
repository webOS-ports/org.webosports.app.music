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

import LuneOS.Service 1.0
import MusicApp 1.0

import "js/Library.js" as Library

/*
 * The music on the device, from the media indexer's songs in db8
 * (com.palm.media.audio.file:1), with what the indexer leaves out filled in
 * by TagReader from the files themselves.
 *
 * Reading the indexer's kinds takes the user's permission once: db8 refuses
 * an app it has no grant for (-3963), and com.palm.mediapermissions then
 * asks the user and has the indexer grant read access.
 */
Item {
    id: store

    readonly property string kind: "com.palm.media.audio.file:1"

    // { songs, albums, artists, genres, byPath } (js/Library.js)
    property var lib: Library.index([])
    // Bumped whenever lib changes; views rebuild on it.
    property int revision: 0
    // "loading", "ready", "empty", "denied" or "error"
    property string status: "loading"
    property string errorText: ""
    readonly property bool enriching: tagReader.busy
    property alias tagReader: tagReader

    property string clientName: "org.webosports.app.music"
    // How long to wait for com.palm.mediapermissions: an image without it
    // (the TouchPad's) never answers, and the library would load forever.
    property int permissionTimeout: 15000
    // function(uri, json, onReply, onError): the permission request on the
    // bus, replaceable by the tests.
    property var permissionCall: function(uri, json, onReply, onError) {
        permissions.call(uri, json, onReply, onError);
    }
    property string cacheDir: ""

    // The songs as they are now; lib is rebuilt from these.
    property var _songs: []
    property bool _asked: false
    property bool _loaded: false

    // The indexer's songs, every page, found again when they change; the
    // kind is set by the first load().
    Db8Model {
        id: indexed
        query: ({
            select: ["_id", "path", "title", "artist", "albumArtist", "album", "genre",
                     "track", "disc", "duration", "modifiedTime", "isRingtone"],
            limit: 500
        })
        allPages: true
        watch: true
        onStatusChanged: {
            if (status !== "ready")
                return;
            // The first answer at once; the indexer then adds songs in
            // bursts while it scans, so later ones wait for it to settle.
            if (!store._loaded)
                store._takeRecords();
            else
                reloadTimer.restart();
        }
        onError: function(errorText, errorCode) {
            if (errorCode === -3963 && !store._asked) {
                store._asked = true;
                store._askPermission();
                return;
            }
            store.errorText = errorText;
            store.status = errorCode === -3963 ? "denied" : "error";
        }
    }

    LunaService {
        id: permissions
        name: store.clientName
    }

    TagReader {
        id: tagReader
        cacheFile: store.cacheDir !== "" ? store.cacheDir + "/tags.json" : ""
        onEnriched: function(batch) {
            var byPath = store.lib.byPath;
            for (var i = 0; i < batch.length; i++) {
                var song = byPath[batch[i].path];
                if (song)
                    Library.enrich(song, batch[i]);
            }
            rebuildTimer.restart();
        }
        onFinished: store._rebuild()
    }

    // Many batches arrive in a row on a first run; the views are rebuilt
    // once they pause.
    Timer {
        id: rebuildTimer
        interval: 1200
        onTriggered: store._rebuild()
    }

    Timer {
        id: permissionTimer
        interval: store.permissionTimeout
        onTriggered: {
            store.errorText = "Music cannot ask for access to the music library: the permission service does not answer.";
            store.status = "error";
        }
    }

    Timer {
        id: reloadTimer
        interval: 3000
        onTriggered: store._takeRecords()
    }

    function load() {
        if (_songs.length === 0)
            status = "loading";
        if (indexed.kind === "")
            indexed.kind = kind;
        else
            indexed.refresh();
    }

    function _takeRecords() {
        var records = [];
        for (var i = 0; i < indexed.count; i++)
            records.push(indexed.get(i));
        _loaded = true;
        setRecords(records);
    }

    function _askPermission() {
        status = "loading";
        permissionTimer.restart();
        permissionCall("luna://com.palm.mediapermissions/request",
                       JSON.stringify({ rights: { read: [kind] } }),
                       function(message) {
                           permissionTimer.stop();
                           var r = JSON.parse(message.payload);
                           if (r.isAllowed)
                               store.load();
                           else
                               store.status = "denied";
                       }, function() {
                           permissionTimer.stop();
                           store.status = "denied";
                       });
    }

    /* Asks again after "Don't Allow" (the Allow button on the notice). */
    function retryPermission() {
        _asked = true;
        _askPermission();
    }

    /* The library from indexer records (also what the tests feed in). */
    function setRecords(records) {
        // Keep what TagReader already found for songs that did not change.
        var old = lib.byPath;
        var built = Library.build(records);
        built.songs.forEach(function(s) {
            var before = old[s.path];
            if (before && before.enriched && before.modified === s.modified)
                Library.enrich(s, before);
        });
        _songs = built.songs;
        _rebuild();
        status = _songs.length > 0 ? "ready" : "empty";
        if (_songs.length > 0)
            tagReader.enrich(_songs.map(function(s) { return { path: s.path, modified: s.modified }; }));
    }

    function _rebuild() {
        rebuildTimer.stop();
        // Files that are gone stay out, though the indexer still lists them.
        lib = Library.index(_songs.filter(function(s) { return !s.missing; }));
        revision++;
        if (status === "ready" && lib.songs.length === 0)
            status = "empty";
    }

    function song(path) {
        return lib.byPath[path] || null;
    }

    /* The library's song for path, or one made from the file name (a
     * file opened from Files, a card the indexer does not scan). */
    function trackFor(path) {
        return lib.byPath[path] || Library.normalize({ path: path });
    }

    /* Tracks for a playlist's entries: paths, or a streamed track's stored
     * object (js/Streaming.js stored()). */
    function tracksFor(entries) {
        return entries.map(function(e) { return typeof e === "object" && e !== null ? e : store.trackFor(e); });
    }

    function album(key) {
        for (var i = 0; i < lib.albums.length; i++) {
            if (lib.albums[i].key === key)
                return lib.albums[i];
        }
        return null;
    }

    function artist(name) {
        var lower = String(name).toLowerCase();
        for (var i = 0; i < lib.artists.length; i++) {
            if (lib.artists[i].name.toLowerCase() === lower)
                return lib.artists[i];
        }
        return null;
    }

    function genre(name) {
        var lower = String(name).toLowerCase();
        for (var i = 0; i < lib.genres.length; i++) {
            if (lib.genres[i].name.toLowerCase() === lower)
                return lib.genres[i];
        }
        return null;
    }

    /* The tag data Player's ReplayGain needs, or null. */
    function gainTags(path) {
        return lib.byPath[path] || null;
    }
}
