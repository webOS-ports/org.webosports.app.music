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

import "js/Lyrics.js" as Lyrics
import "js/Streaming.js" as Streaming

/*
 * Lyrics from LRCLIB (lrclib.net), an open database of them, for a song
 * with none of its own: every streamed one, and files without lyrics in
 * their tags. It is asked with the song's artist and title.
 */
QtObject {
    id: lookup

    // The preference: off, nothing is looked up.
    property bool enabled: true
    property string baseUrl: "https://lrclib.net/api"
    // function(url, done(httpStatus, jsonOrNull)): the HTTP call, replaceable
    // by the tests.
    property var transport: _xhr
    // function(providerId) -> the service's name, to tell a streamed track
    // without an artist (js/Streaming.js artistOf).
    property var providerName: Streaming.displayName

    // What was found (or that nothing was) per song, so going back to one
    // does not ask again; a failed request is not kept.
    property var _found: ({})
    property int _kept: 0

    /* done(result): { text, instrumental }, or null when there are none. */
    function find(track, done) {
        if (!enabled || !track || !track.title) {
            done(null);
            return;
        }
        var artist = _artistOf(track);
        var durationMs = track.duration > 0 ? track.duration : 0;
        var key = artist + "\u0000" + track.title + "\u0000" + Math.round(durationMs / 1000);
        if (_found.hasOwnProperty(key)) {
            done(_found[key]);
            return;
        }
        var titles = [String(track.title)];
        var shorter = Lyrics.searchTitle(track.title);
        if (shorter !== "" && shorter !== titles[0])
            titles.push(shorter);
        var tryTitle = function(i) {
            if (i >= titles.length) {
                lookup._keep(key, null);
                done(null);
                return;
            }
            lookup.transport(lookup._searchUrl(artist, titles[i]), function(status, data) {
                var result = status === 200 ? Lyrics.pickOnline(data, durationMs) : null;
                if (result) {
                    lookup._keep(key, result);
                    done(result);
                } else if (status === 200 || status === 404) {
                    tryTitle(i + 1);
                } else {
                    done(null); // offline, or refused: asked again next time
                }
            });
        };
        tryTitle(0);
    }

    function _searchUrl(artist, title) {
        if (artist === "")
            return baseUrl + "/search?q=" + encodeURIComponent(title);
        return baseUrl + "/search?track_name=" + encodeURIComponent(title)
               + "&artist_name=" + encodeURIComponent(artist);
    }

    // A streamed track whose service gave no artist carries the service's
    // name as artist and album (js/Streaming.js): that is no artist to ask by.
    function _artistOf(track) {
        return Streaming.artistOf(track, track.remote ? providerName(track.provider) : "");
    }

    function _keep(key, result) {
        if (_kept >= 200) {
            _found = {};
            _kept = 0;
        }
        _found[key] = result;
        _kept++;
    }

    function _xhr(url, done) {
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
        req.open("GET", url);
        // LRCLIB asks its clients to say who they are.
        req.setRequestHeader("User-Agent", "Music for LuneOS (https://github.com/webOS-ports/org.webosports.app.music)");
        req.send();
    }
}
