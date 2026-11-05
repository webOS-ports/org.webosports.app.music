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

import "js/Podcasts.js" as Podcasts

/*
 * Podcasts, as the music streaming service keeps them: it has the user's
 * podcasts, reads their feeds, downloads episodes and remembers where each
 * one was left, also while this app is closed. This is its client: the
 * lists the Podcasts tab and Home show, and the calls that change them.
 *
 * Episodes play as tracks "podcast:<podcast>.<episode>"; resolve() gives
 * what plays one (the downloaded file, or the feed's link).
 */
Item {
    id: store

    property string baseUrl: "http://127.0.0.1:8730"
    // function(method, url, body, done(httpStatus, jsonOrNull)), as the
    // streaming store's; the tests replace it there.
    property var transport: null

    // The user's podcasts, by title, and what the service is doing.
    property var podcasts: []
    property bool refreshing: false
    property int downloading: 0
    // Episodes: the new ones, those started and not finished, and those
    // downloaded or on their way.
    property var newEpisodes: []
    property var inProgress: []
    property var downloads: []
    property var settings: ({ refreshHours: 6, wifiOnly: true, autoDownload: 0, keepPlayedDays: 7, notify: true })
    // "unknown", "ready" or "unavailable" (the service does not answer, or
    // has no podcasts yet: an older one).
    property string status: "unknown"
    readonly property bool available: status === "ready"
    // Goes up with every change, for lists that show episodes.
    property int revision: 0
    // Where each episode was left, in ms, by track path: what the player
    // resumes at, without asking.
    property var _positions: ({})

    function _call(method, path, body, done) {
        var t = transport || _xhr;
        t(method, baseUrl + path, body === undefined ? null : body, function(code, data) {
            if (done)
                done(code === 200 && data ? data : null, code === 200 ? "" : Podcasts.errorOf(code, data));
        });
    }

    function _xhr(method, url, body, done) {
        var req = new XMLHttpRequest();
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            try {
                data = req.responseText ? JSON.parse(req.responseText) : null;
            } catch (e) {
                data = null;
            }
            done(req.status, data);
        };
        req.open(method, url);
        if (body !== null) {
            req.setRequestHeader("Content-Type", "application/json");
            req.send(JSON.stringify(body));
        } else {
            req.send();
        }
    }

    function _remember(episodes) {
        var p = _positions;
        (episodes || []).forEach(function(e) {
            p[e.id] = e.played ? 0 : (e.position_ms || 0);
        });
    }

    /* Asks the service for everything the tab shows. */
    function refresh() {
        _call("GET", "/podcasts", null, function(data) {
            if (!data || !Array.isArray(data.podcasts)) {
                status = "unavailable";
                return;
            }
            podcasts = data.podcasts;
            refreshing = data.refreshing === true;
            downloading = data.downloading > 0 ? data.downloading : 0;
            status = "ready";
            _lists();
        });
        _call("GET", "/podcasts/settings", null, function(data) {
            if (data && typeof data.refreshHours === "number")
                settings = data;
        });
    }

    function _lists() {
        _call("GET", "/podcasts/new?limit=100", null, function(data) {
            if (data && Array.isArray(data.episodes)) {
                newEpisodes = data.episodes;
                _remember(data.episodes);
                revision++;
            }
        });
        _call("GET", "/podcasts/inprogress?limit=50", null, function(data) {
            if (data && Array.isArray(data.episodes)) {
                inProgress = data.episodes;
                _remember(data.episodes);
                revision++;
            }
        });
        _call("GET", "/podcasts/downloads", null, function(data) {
            if (data && Array.isArray(data.episodes)) {
                downloads = data.episodes;
                _remember(data.episodes);
                revision++;
            }
        });
    }

    // While the service refreshes or downloads, its lists change by
    // themselves: ask again now and then.
    Timer {
        interval: 2000
        repeat: true
        running: store.available && (store.refreshing || store.downloading > 0)
        onTriggered: store.refresh()
    }

    function podcast(id) {
        for (var i = 0; i < podcasts.length; i++) {
            if (podcasts[i].id === id)
                return podcasts[i];
        }
        return null;
    }

    function subscribedId(url) {
        for (var i = 0; i < podcasts.length; i++) {
            if (podcasts[i].url === url)
                return podcasts[i].id;
        }
        return "";
    }

    /* done(results, error): podcasts to subscribe to. */
    function search(query, done) {
        _call("GET", "/podcasts/search?limit=30&q=" + encodeURIComponent(query), null, function(data, error) {
            done(data && Array.isArray(data.results) ? data.results : [], error);
        });
    }

    /* done({ podcast, episodes }, error): a podcast not subscribed to. */
    function preview(url, done) {
        _call("POST", "/podcasts/preview", { url: url }, function(data, error) {
            if (data)
                _remember(data.episodes);
            done(data, error);
        });
    }

    function subscribe(url, done) {
        _call("POST", "/podcasts/subscribe", { url: url }, function(data, error) {
            if (data)
                refresh();
            if (done)
                done(data ? data.podcast : null, error);
        });
    }

    function unsubscribe(id, deleteDownloads, done) {
        _call("POST", "/podcasts/unsubscribe", { id: id, deleteDownloads: deleteDownloads === true }, function(data, error) {
            refresh();
            if (done)
                done(error);
        });
    }

    /* done(episodes, error, next): a page of a podcast's episodes, newest
     * first; next is where the page after it starts, -1 at the end. */
    function episodes(id, offset, done) {
        _call("GET", "/podcasts/episodes?limit=50&id=" + encodeURIComponent(id) + "&offset=" + (offset || 0), null,
              function(data, error) {
            if (!data || !Array.isArray(data.episodes)) {
                done([], error, -1);
                return;
            }
            _remember(data.episodes);
            done(data.episodes, "", data.more === true ? data.next : -1);
        });
    }

    /* Changes an episode: { position_ms, played, new }. done(episode). */
    function setState(id, fields, done) {
        var body = { id: id };
        for (var k in fields)
            body[k] = fields[k];
        if (typeof fields.position_ms === "number")
            _positions[id] = fields.position_ms;
        if (fields.played === true)
            _positions[id] = 0;
        _call("POST", "/podcasts/state", body, function(data) {
            if (data && data.episode)
                _remember([data.episode]);
            _lists();
            if (done)
                done(data ? data.episode : null);
        });
    }

    function markAll(podcastId, fields, done) {
        var body = { podcast: podcastId };
        for (var k in fields)
            body[k] = fields[k];
        _call("POST", "/podcasts/markall", body, function() {
            refresh();
            if (done)
                done();
        });
    }

    /* Reads the feeds again: one podcast's, or all. */
    function refreshFeeds(id) {
        _call("POST", "/podcasts/refresh", id ? { id: id } : {}, function(data) {
            if (data)
                refreshing = true;
            refresh();
        });
    }

    function download(id, done) {
        _call("POST", "/podcasts/download", { id: id }, function(data, error) {
            refresh();
            if (done)
                done(data ? data.episode : null, error);
        });
    }

    function cancelDownload(id, done) {
        _call("POST", "/podcasts/download/cancel", { id: id }, function(data) {
            refresh();
            if (done)
                done(data ? data.episode : null);
        });
    }

    function deleteDownload(id, done) {
        _call("POST", "/podcasts/download/delete", { id: id }, function(data) {
            refresh();
            if (done)
                done(data ? data.episode : null);
        });
    }

    /* done(url, error, video): what plays an episode's track. */
    function resolve(track, done) {
        var id = String(track.path || "").replace(/^podcast:/, "");
        _call("POST", "/podcasts/resolve", { trackId: id }, function(data, error) {
            if (data && data.url)
                done(data.url, "", data.video === true);
            else
                done("", error || "The podcast service is not running.", false);
        });
    }

    /* Where an episode was left, in ms: 0 at its start, or when finished. */
    function positionOf(path) {
        return _positions[path] || 0;
    }

    function saveSettings(changes, done) {
        _call("POST", "/podcasts/settings", changes, function(data) {
            if (data && typeof data.refreshHours === "number")
                settings = data;
            if (done)
                done(data);
        });
    }

    function setAutoDownload(id, count, done) {
        _call("POST", "/podcasts/feedsettings", { id: id, autoDownload: count }, function(data) {
            refresh();
            if (done)
                done(data ? data.podcast : null);
        });
    }

    /* done(path, error): the podcasts written out as OPML. */
    function exportOpml(done) {
        _call("POST", "/podcasts/opml/export", {}, function(data, error) {
            done(data && data.path ? data.path : "", error);
        });
    }

    /* done(files): the OPML files on the device, [{ path, name, modified }]. */
    function opmlFiles(done) {
        _call("GET", "/podcasts/opml/files", null, function(data) {
            done(data && Array.isArray(data.files) ? data.files : []);
        });
    }

    /* what: { path } of a file, { url } or { opml } text.
     * done({ added, skipped, failed }, error). */
    function importOpml(what, done) {
        _call("POST", "/podcasts/opml/import", what, function(data, error) {
            refresh();
            done(data, error);
        });
    }
}
