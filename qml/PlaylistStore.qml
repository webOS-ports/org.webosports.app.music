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

/*
 * The user's playlists, in the app's own db8 kind:
 *
 *     { name, tracks: [path...], created (ms), modified (ms) }
 *
 * Tracks are paths, not indexer ids: an id changes when the indexer scans a
 * file afresh, a path only when the file moves.
 */
Item {
    id: store

    readonly property string kind: "org.webosports.app.music.playlist:1"
    property string clientName: "org.webosports.app.music"

    // [{ _id, name, tracks, created, modified }], by name.
    property var playlists: []
    property int revision: 0
    property bool ready: false

    signal failed(string text)

    // The app's kind: registered, then read once, every page; after that
    // the list here is the truth and only written.
    Db8Model {
        id: db
        query: ({ limit: 500 })
        allPages: true
        onStatusChanged: {
            if (status !== "ready" || store.ready)
                return;
            var list = [];
            for (var i = 0; i < count; i++)
                list.push(get(i));
            store.playlists = store._sorted(list);
            store.ready = true;
            store.revision++;
        }
        onError: function(errorText) { store.failed("Cannot read playlists: " + errorText); }
    }

    function load() {
        db.putKind({
            id: kind,
            owner: clientName,
            indexes: [{ name: "name", props: [{ name: "name", collate: "primary" }] }]
        }, function(reply) {
            if (reply.returnValue)
                db.kind = kind;
            else
                store.failed("Cannot set up playlists: " + reply.errorText);
        });
    }

    function _sorted(list) {
        return list.slice().sort(function(a, b) {
            return String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase());
        });
    }

    function _replace(playlist) {
        var list = playlists.filter(function(p) { return p._id !== playlist._id; });
        list.push(playlist);
        playlists = _sorted(list);
        revision++;
    }

    function byId(id) {
        for (var i = 0; i < playlists.length; i++) {
            if (playlists[i]._id === id)
                return playlists[i];
        }
        return null;
    }

    function byName(name) {
        var lower = String(name).trim().toLowerCase();
        for (var i = 0; i < playlists.length; i++) {
            if (String(playlists[i].name).toLowerCase() === lower)
                return playlists[i];
        }
        return null;
    }

    /* A name not yet taken: "Name", else "Name 2", "Name 3"... */
    function uniqueName(name) {
        var base = String(name).trim() || "Playlist";
        if (!byName(base))
            return base;
        for (var n = 2; ; n++) {
            if (!byName(base + " " + n))
                return base + " " + n;
        }
    }

    /* Makes a playlist; done(playlist) once it is stored. */
    function create(name, paths, done) {
        var now = Date.now();
        var p = { _kind: kind, name: uniqueName(name), tracks: paths.slice(), created: now, modified: now };
        db.put([p], function(reply) {
            if (reply.returnValue === false) {
                store.failed("Cannot save the playlist: " + reply.errorText);
                return;
            }
            var res = (reply.results || [])[0];
            if (res && (res.id || res._id))
                p._id = res.id || res._id;
            store._replace(p);
            if (done)
                done(p);
        });
    }

    function _save(p) {
        p.modified = Date.now();
        _replace(p);
        db.merge([{ _id: p._id, _kind: kind, name: p.name, tracks: p.tracks, modified: p.modified }], function(reply) {
            if (reply.returnValue === false)
                store.failed("Cannot save the playlist: " + reply.errorText);
        });
    }

    function add(id, paths) {
        var p = byId(id);
        if (!p)
            return;
        p.tracks = p.tracks.concat(paths);
        _save(p);
    }

    function rename(id, name) {
        var p = byId(id);
        var clean = String(name).trim();
        if (!p || clean === "" || clean === p.name)
            return;
        var other = byName(clean);
        p.name = other && other._id !== id ? uniqueName(clean) : clean;
        _save(p);
    }

    function removeAt(id, index) {
        var p = byId(id);
        if (!p || index < 0 || index >= p.tracks.length)
            return;
        var tracks = p.tracks.slice();
        tracks.splice(index, 1);
        p.tracks = tracks;
        _save(p);
    }

    function move(id, from, to) {
        var p = byId(id);
        if (!p || from === to || from < 0 || to < 0 || from >= p.tracks.length || to >= p.tracks.length)
            return;
        var tracks = p.tracks.slice();
        var moved = tracks.splice(from, 1)[0];
        tracks.splice(to, 0, moved);
        p.tracks = tracks;
        _save(p);
    }

    function remove(id) {
        db.del([id], function(reply) {
            if (reply.returnValue === false) {
                store.failed("Cannot delete the playlist: " + reply.errorText);
                return;
            }
            store.playlists = store.playlists.filter(function(p) { return p._id !== id; });
            store.revision++;
        });
    }
}
