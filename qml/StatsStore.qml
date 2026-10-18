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
 * What the user did with each song - plays, skips, when last played, the
 * favourite heart, where a long track was left - in the app's own db8 kind,
 * one record per song:
 *
 *     { path, playCount, skipCount, lastPlayed (ms), favorite, bookmark (ms) }
 *
 * The media indexer's kinds are not the app's to write to, and a re-scan
 * would lose anything kept there.
 */
Item {
    id: stats

    readonly property string kind: "org.webosports.app.music.stats:1"
    property string clientName: "org.webosports.app.music"

    // { path: record }
    property var byPath: ({})
    // Bumped on every change, for the views and the smart playlists.
    property int revision: 0
    property bool ready: false

    // Records written since the last flush, by path.
    property var _dirty: ({})

    Db8 {
        id: db
        clientName: stats.clientName
    }

    function load() {
        db.putKind({
            id: kind,
            owner: clientName,
            indexes: [
                { name: "path", props: [{ name: "path" }] },
                { name: "lastPlayed", props: [{ name: "lastPlayed" }] }
            ]
        }, function() {
            db.findAll({ from: kind }, function(results) {
                var map = {};
                results.forEach(function(r) { if (r.path) map[r.path] = r; });
                stats.byPath = map;
                stats.ready = true;
                stats.revision++;
            }, function(error) { console.warn("Music: cannot read play counts: " + error); });
        }, function(error) { console.warn("Music: cannot register " + kind + ": " + error); });
    }

    function get(path) {
        return byPath[path] || null;
    }

    function _record(path) {
        var r = byPath[path];
        if (!r) {
            r = { _kind: kind, path: path, playCount: 0, skipCount: 0, lastPlayed: 0, favorite: false, bookmark: 0 };
            byPath[path] = r;
        }
        return r;
    }

    function _changed(r) {
        _dirty[r.path] = r;
        revision++;
        flushTimer.restart();
    }

    /*
     * A track stopped. It counts as played when it got through half its
     * length or four minutes, whichever comes first, and is at least 30 s
     * long - Last.fm's rule, which Music Player Remix and most players
     * follow; time skipped over by seeking does not count. It counts as
     * skipped when it was left early.
     */
    function isPlay(lengthMs, playedMs, completed) {
        if (lengthMs > 0 && lengthMs < 30000)
            return false;
        if (completed)
            return true;
        var needed = lengthMs > 0 ? Math.min(lengthMs / 2, 240000) : 240000;
        return playedMs >= needed;
    }

    function trackFinished(track, playedMs, completed) {
        if (!track || !track.path)
            return;
        var length = track.duration || 0;
        var played = isPlay(length, playedMs, completed);
        var r = _record(track.path);
        if (played) {
            r.playCount = (r.playCount || 0) + 1;
            r.lastPlayed = Date.now();
            if (completed)
                r.bookmark = 0;
        } else if (!completed && playedMs > 1000) {
            r.skipCount = (r.skipCount || 0) + 1;
        } else {
            return;
        }
        _changed(r);
    }

    function isFavorite(path) {
        var r = byPath[path];
        return !!(r && r.favorite);
    }

    function setFavorite(path, on) {
        var r = _record(path);
        if (!!r.favorite === !!on)
            return;
        r.favorite = !!on;
        _changed(r);
    }

    function bookmarkOf(path) {
        var r = byPath[path];
        return r && r.bookmark > 0 ? r.bookmark : 0;
    }

    function setBookmark(path, ms) {
        var r = _record(path);
        var value = Math.max(0, Math.round(ms));
        if (Math.abs((r.bookmark || 0) - value) < 1000)
            return;
        r.bookmark = value;
        _dirty[r.path] = r;
        flushTimer.restart();
    }

    /* The plain { path: { playCount, lastPlayed, favorite } } map the smart
     * playlists read. */
    function asMap() {
        return byPath;
    }

    /* Writes what changed: put for new records, merge for known ones. */
    function flush() {
        flushTimer.stop();
        var fresh = [], known = [], later = {};
        var waiting = false;
        for (var path in _dirty) {
            var r = _dirty[path];
            // Its first put has not answered yet: a second put now would
            // store it twice. It goes out as a merge once the id is known.
            if (!r._id && r._pending) {
                later[path] = r;
                waiting = true;
                continue;
            }
            var o = { _kind: kind, path: r.path, playCount: r.playCount || 0, skipCount: r.skipCount || 0,
                      lastPlayed: r.lastPlayed || 0, favorite: !!r.favorite, bookmark: r.bookmark || 0 };
            if (r._id) {
                o._id = r._id;
                known.push(o);
            } else {
                r._pending = true;
                fresh.push(o);
            }
        }
        _dirty = later;
        if (waiting)
            flushTimer.restart();
        if (known.length)
            db.merge(known, null, function(error) { console.warn("Music: cannot save play counts: " + error); });
        if (fresh.length) {
            db.put(fresh, function(reply) {
                (reply.results || []).forEach(function(res, i) {
                    var rec = stats.byPath[fresh[i].path];
                    if (rec) {
                        rec._pending = false;
                        if (res.id || res._id)
                            rec._id = res.id || res._id;
                    }
                });
            }, function(error) {
                fresh.forEach(function(o) {
                    var rec = stats.byPath[o.path];
                    if (rec)
                        rec._pending = false;
                });
                console.warn("Music: cannot save play counts: " + error);
            });
        }
    }

    Timer {
        id: flushTimer
        interval: 2000
        onTriggered: stats.flush()
    }
}
