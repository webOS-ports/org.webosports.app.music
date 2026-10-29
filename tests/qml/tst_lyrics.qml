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
import QtTest

import "../../qml"

/*
 * LyricsLookup against a fake LRCLIB: what it asks, which answer it takes,
 * and what it remembers.
 */
TestCase {
    name: "LyricsLookup"

    property var asked: []
    property var answers: ({})
    function fakeLrclib(url, done) {
        asked = asked.concat([url]);
        var a = answers[url];
        if (typeof a === "function")
            a = a(url);
        done(a ? a[0] : 404, a ? a[1] : null);
    }

    property var waited: []
    function noWait(ms, fn) {
        waited = waited.concat([ms]);
        fn();
    }

    LyricsLookup {
        id: lookup
        transport: fakeLrclib
        delay: noWait
    }

    readonly property string base: "https://lrclib.net/api/search?"
    function q(title, artist) {
        return artist === undefined ? base + "q=" + encodeURIComponent(title)
            : base + "track_name=" + encodeURIComponent(title) + "&artist_name=" + encodeURIComponent(artist);
    }
    property bool lastFailed: false
    function find(track) {
        var got = undefined;
        lookup.find(track, function(r, failed) {
            got = r;
            lastFailed = failed === true;
        });
        verify(got !== undefined, "answered at once by the fake");
        return got;
    }

    function init() {
        asked = [];
        answers = {};
        waited = [];
        lookup.enabled = true;
        lookup._found = {};
        lookup._kept = 0;
    }

    function test_asks_by_artist_and_title_and_remembers() {
        answers[q("Get Lucky", "Daft Punk")] = [200, [{ duration: 248, syncedLyrics: "[00:01.00]Like the legend", plainLyrics: "x" }]];
        var track = { path: "/m/gl.flac", title: "Get Lucky", artist: "Daft Punk", album: "RAM", duration: 248000 };
        compare(find(track), { text: "[00:01.00]Like the legend", instrumental: false });
        compare(asked, [q("Get Lucky", "Daft Punk")]);
        // Again: from what it found, no request.
        compare(find(track).text, "[00:01.00]Like the legend");
        compare(asked.length, 1);
    }

    function test_a_shorter_title_when_the_whole_finds_nothing() {
        answers[q("Get Lucky (Official Audio)", "Daft Punk")] = [200, []];
        answers[q("Get Lucky", "Daft Punk")] = [200, [{ duration: 248, plainLyrics: "Plain" }]];
        var r = find({ path: "youtube:abc", title: "Get Lucky (Official Audio)", artist: "Daft Punk",
                       album: "YouTube Music", duration: 248000, remote: true });
        compare(r, { text: "Plain", instrumental: false });
        compare(asked, [q("Get Lucky (Official Audio)", "Daft Punk"), q("Get Lucky", "Daft Punk")]);
    }

    function test_a_streamed_track_without_artist_is_asked_by_title() {
        answers[q("Some Song")] = [200, [{ duration: 200, plainLyrics: "Words" }]];
        // js/Streaming.js gives a track without artist its service's name as both.
        var r = find({ path: "soundcloud:1", title: "Some Song", artist: "SoundCloud", album: "SoundCloud",
                       duration: 200000, remote: true });
        compare(r.text, "Words");
        compare(asked, [q("Some Song")]);
    }

    function test_nothing_found_is_remembered_a_failure_is_not() {
        var track = { path: "/m/x.mp3", title: "Unknown", artist: "Nobody", album: "A", duration: 100000 };
        answers[q("Unknown", "Nobody")] = [200, []];
        compare(find(track), null);
        compare(find(track), null);
        compare(asked.length, 1);
        verify(!lastFailed, "nothing there is not a failure");
        // Offline: not kept, asked again the next time.
        var other = { path: "/m/y.mp3", title: "Offline", artist: "Nobody", album: "A", duration: 100000 };
        answers[q("Offline", "Nobody")] = [0, null];
        compare(find(other), null);
        verify(lastFailed, "offline is a failure");
        compare(find(other), null);
        compare(asked.length, 1 + 2 * 3);
    }

    // LRCLIB when it is busy, as seen from the MindPhone (2026-10-29): 503
    // {"name":"ServerOverloaded"} for one request, 200 for the next.
    function test_a_busy_server_is_asked_again_after_a_pause() {
        var tries = 0;
        answers[q("Wonderful World", "Art Garfunkel")] = function() {
            return ++tries < 3 ? [503, { name: "ServerOverloaded", statusCode: 503 }]
                               : [200, [{ duration: 209, plainLyrics: "What a wonderful world" }]];
        };
        var r = find({ path: "spotify:track:1", title: "Wonderful World", artist: "Art Garfunkel",
                       album: "A", duration: 209000, remote: true });
        compare(r, { text: "What a wonderful world", instrumental: false });
        verify(!lastFailed);
        compare(asked.length, 3);
        compare(waited, [1000, 3000]);
    }

    function test_a_server_busy_throughout_is_a_failure_not_kept() {
        var track = { path: "spotify:track:2", title: "Busy", artist: "Nobody", album: "A", duration: 1000, remote: true };
        answers[q("Busy", "Nobody")] = [503, null];
        compare(find(track), null);
        verify(lastFailed, "told apart from nothing found");
        compare(asked.length, 3);
        // Once it answers, the same song is found: the failure was not kept.
        answers[q("Busy", "Nobody")] = [200, [{ duration: 1, plainLyrics: "Now" }]];
        compare(find(track).text, "Now");
        verify(!lastFailed);
    }

    function test_a_refusal_is_not_asked_again() {
        var track = { path: "/m/r.mp3", title: "Refused", artist: "Nobody", album: "A", duration: 1000 };
        answers[q("Refused", "Nobody")] = [429, null];
        compare(find(track), null);
        verify(lastFailed);
        compare(asked.length, 1);
        compare(waited, []);
    }

    function test_off_asks_nothing() {
        lookup.enabled = false;
        compare(find({ path: "/m/z.mp3", title: "Song", artist: "A", album: "B", duration: 1000 }), null);
        compare(asked.length, 0);
    }
}
