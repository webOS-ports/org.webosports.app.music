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
import "../../qml/js/Streaming.js" as Streaming
import "../../qml/js/Queue.js" as Queue

/*
 * Streaming: the track objects and paths (js/Streaming.js), StreamingStore
 * against a fake music streaming service, Player resolving streamed tracks
 * (to the fixture files, standing in for the web), and SpotifyEngine's
 * Connect control and its guess at the end of a track.
 */
Item {
    id: root
    width: 200
    height: 200

    readonly property string fixtures: String(Qt.resolvedUrl("../fixtures/music")).replace(/^file:\/\//, "")

    // The fake daemon: answers by method and path, and records the calls.
    property var calls: []
    property var answers: ({})
    function fakeTransport(method, url, body, done) {
        var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "");
        root.calls = root.calls.concat([{ method: method, path: path, body: body }]);
        var key = method + " " + path.replace(/\?.*$/, "");
        var a = root.answers[key];
        if (typeof a === "function")
            a = a(body, path);
        if (!a)
            a = [404, { error: "not here" }];
        done(a[0], a[1]);
    }

    StreamingStore {
        id: store
        transport: root.fakeTransport
    }

    Player {
        id: player
        replayGain: "off"
        urlResolver: function(track, done) { store.resolve(track, done); }
        streamingTransport: root.fakeTransport
    }

    SpotifyEngine {
        id: spotify
        transport: root.fakeTransport
    }

    SignalSpy {
        id: endSpy
        target: spotify
        signalName: "endOfMedia"
    }

    TestCase {
        name: "StreamingJs"

        function test_split() {
            compare(Streaming.split("youtube:abc"), { provider: "youtube", id: "abc" });
            compare(Streaming.split("spotify:track:9x"), { provider: "spotify", id: "track:9x" });
            compare(Streaming.split("/media/internal/a.mp3"), null);
            compare(Streaming.split("file:///a.mp3"), null);
            verify(Streaming.isSpotify("spotify:track:1"));
            verify(!Streaming.isSpotify("tidal:1"));
            verify(Streaming.isRemote("tidal:1"));
            verify(!Streaming.isRemote("/a.mp3"));
        }

        function test_track() {
            var t = Streaming.track({ id: "42", provider: "tidal", title: "T", artist: "A", album: "",
                                      thumbnail: "https://img/1.jpg", duration_ms: 123000, path: "tidal:42" }, "Tidal");
            compare(t.path, "tidal:42");
            compare(t.album, "Tidal");
            compare(t.duration, 123000);
            compare(t.artUrl, "https://img/1.jpg");
            verify(t.remote);
            compare(Streaming.track({ id: "7", provider: "jamendo" }).path, "jamendo:7");
        }

        function test_signed_in() {
            var daemon = [{ id: "youtube", name: "YouTube" }, { id: "tidal", name: "Tidal" },
                          { id: "qobuz", name: "Qobuz" }, { id: "deezer", name: "Deezer" }];
            // Qobuz's account was removed; the daemon still has its token.
            var accounts = ["org.webosports.app.music.tidal", "org.webosports.app.music.deezer", "com.palm.google"];
            compare(Streaming.signedIn(daemon, accounts).map(function(p) { return p.id; }), ["deezer", "tidal", "youtube"]);
            // Accounts could not be asked: the daemon's list stands.
            compare(Streaming.signedIn(daemon, null).length, 4);
            compare(Streaming.signedIn(null, accounts).length, 0);
        }

        function test_stored() {
            compare(Streaming.stored({ path: "/a.mp3", title: "x" }), "/a.mp3");
            var s = Streaming.stored({ path: "tidal:1", title: "T", artist: "A", album: "B", duration: 5,
                                       artUrl: "u", provider: "tidal", remote: true, extra: 1 });
            compare(s.path, "tidal:1");
            compare(s.artUrl, "u");
            verify(s.extra === undefined);
        }

        function test_queue_keeps_stream_fields() {
            var q = Queue.setTracks(Queue.create(), [{ path: "tidal:1", title: "T", artUrl: "u", provider: "tidal", remote: true }], 0, false);
            var r = Queue.deserialize(Queue.serialize(q, 0));
            compare(r.items[0].artUrl, "u");
            compare(r.items[0].provider, "tidal");
            verify(r.items[0].remote);
        }
    }

    TestCase {
        name: "StreamingStore"

        function init() {
            root.calls = [];
            root.answers = {};
        }

        function test_unavailable_without_daemon() {
            store.refresh();
            tryCompare(store, "status", "unavailable");
            verify(!store.available);
            compare(store.providers.length, 0);
        }

        function test_providers_and_search() {
            root.answers["GET /providers"] = [200, { providers: [{ id: "youtube", name: "YouTube" }, { id: "jamendo", name: "Jamendo" }] }];
            root.answers["GET /provider/jamendo/search"] = function(body, path) {
                verify(path.indexOf("q=blue%20sky") > 0);
                verify(path.indexOf("limit=5") > 0);
                return [200, { tracks: [{ id: "9", provider: "jamendo", title: "Blue", artist: "Sky", path: "jamendo:9" }] }];
            };
            store.refresh();
            tryCompare(store, "status", "ready");
            verify(store.available);
            compare(store.providerName("jamendo"), "Jamendo");
            var got = null;
            store.search("jamendo", " blue sky ", 5, function(tracks) { got = tracks; });
            tryVerify(function() { return got !== null; });
            compare(got.length, 1);
            compare(got[0].path, "jamendo:9");
            verify(got[0].remote);
            // Nothing typed: no request.
            var before = root.calls.length;
            store.search("jamendo", "  ", 5, function(tracks) { got = tracks; });
            compare(root.calls.length, before);
        }

        function test_search_error() {
            root.answers["GET /provider/tidal/search"] = [502, { error: "tidal: 401" }];
            var err = null;
            store.search("tidal", "x", 5, function(tracks, e) { err = e; });
            tryVerify(function() { return err !== null; });
            compare(err, "tidal: 401");
        }

        function test_resolve() {
            root.answers["POST /provider/tidal/resolve"] = function(body) {
                compare(body.trackId, "42");
                return [200, { url: "http://127.0.0.1:8730/tidalstream?id=42" }];
            };
            var url = null;
            store.resolve({ path: "tidal:42" }, function(u) { url = u; });
            tryVerify(function() { return url !== null; });
            compare(url, "http://127.0.0.1:8730/tidalstream?id=42");
            var err = null;
            store.resolve({ path: "/local.mp3" }, function(u, e) { err = e; });
            verify(err !== "");
        }
    }

    TestCase {
        name: "PlayerStreams"
        when: windowShown

        function init() {
            root.calls = [];
            root.answers = {};
            player.clearQueue();
        }

        function fileUrl(rel) {
            return "file://" + (root.fixtures + "/" + rel).split("/").map(encodeURIComponent).join("/");
        }

        function test_streamed_track_plays_from_its_resolved_url() {
            root.answers["POST /provider/jamendo/resolve"] = function(body) {
                return [200, { url: fileUrl(body.trackId === "1" ? "Various/Summer Mix/01 Ana Ray - Sun.ogg"
                                                                 : "Various/Summer Mix/02 Cool Cats - Sun.ogg") }];
            };
            player.playTracks([{ path: "jamendo:1", title: "One", remote: true },
                               { path: "jamendo:2", title: "Two", remote: true }], 0, false);
            tryVerify(function() { return player.playing; }, 5000);
            compare(player.active.path, "jamendo:1");
            player.next();
            compare(player.current.title, "Two");
            tryVerify(function() { return player.playing && player.active.path === "jamendo:2"; }, 5000);
            var resolves = root.calls.filter(function(c) { return c.path.indexOf("/resolve") > 0; });
            verify(resolves.length >= 2);
        }

        function test_unresolvable_track_is_skipped() {
            root.answers["POST /provider/jamendo/resolve"] = function(body) {
                if (body.trackId === "bad")
                    return [502, { error: "gone" }];
                return [200, { url: fileUrl("Various/Summer Mix/03 Zed - Sun.ogg") }];
            };
            var failed = [];
            var onFailed = function(track, reason) { failed.push(reason); };
            player.failed.connect(onFailed);
            player.playTracks([{ path: "jamendo:bad", title: "Bad", remote: true },
                               { path: "jamendo:ok", title: "Ok", remote: true }], 0, false);
            tryCompare(player.current, "title", "Ok", 5000);
            tryVerify(function() { return player.playing; }, 5000);
            compare(failed, ["gone"]);
            player.failed.disconnect(onFailed);
        }

        // Jamendo's shared client id is refused now and then: the same
        // track picked again is tried again, and says so when it fails
        // again rather than doing nothing.
        function test_track_that_failed_can_be_picked_again() {
            var attempts = 0;
            root.answers["POST /provider/jamendo/resolve"] = function(body) {
                attempts++;
                if (attempts <= 2)
                    return [502, { error: "jamendo: no audio for " + body.trackId }];
                return [200, { url: fileUrl("Various/Summer Mix/01 Ana Ray - Sun.ogg") }];
            };
            var failed = [];
            var onFailed = function(track, reason) { failed.push(reason); };
            player.failed.connect(onFailed);
            var track = { path: "jamendo:flaky", title: "Flaky", remote: true };
            player.playTracks([track], 0, false);
            tryCompare(failed, "length", 1, 5000);
            verify(!player.playing);
            player.playTracks([track], 0, false);
            tryCompare(failed, "length", 2, 5000);
            compare(failed[1], "jamendo: no audio for flaky");
            player.playTracks([track], 0, false);
            tryVerify(function() { return player.playing && player.active.path === "jamendo:flaky"; }, 5000);
            compare(attempts, 3);
            player.failed.disconnect(onFailed);
            player.pause();
        }

        // A long track carries on where it was left (resumeLookup), playing
        // or paused, also when it has to be resolved first.
        function test_resume_point_is_kept() {
            root.answers["POST /provider/jamendo/resolve"] = [200, { url: fileUrl("Various/Summer Mix/02 Cool Cats - Sun.ogg") }];
            player.resumeLookup = function(track) { return 1500; };
            var tracks = [{ path: fileUrl("Various/Summer Mix/01 Ana Ray - Sun.ogg").replace(/^file:\/\//, "").split("/").map(decodeURIComponent).join("/"),
                            title: "File" },
                          { path: "jamendo:9", title: "Streamed", remote: true }];
            for (var i = 0; i < tracks.length; i++) {
                // Paused: only the seek brings it there.
                player.playTracks([tracks[i]], 0, false);
                player.pause();
                tryVerify(function() { return player.active.seekable && player.active.position >= 1400; }, 5000,
                          tracks[i].title + " paused at " + player.active.position);
                // Playing: within the first second it is past the resume point.
                player.playTracks([tracks[i]], 0, false);
                tryVerify(function() { return player.playing; }, 5000);
                tryVerify(function() { return player.active.position >= 1500; }, 1000,
                          tracks[i].title + " playing at " + player.active.position);
            }
            player.resumeLookup = null;
            player.pause();
        }

        function test_spotify_goes_through_librespot() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 200000 }];
            root.answers["POST /player/pause"] = [200, { ok: true }];
            root.answers["POST /player/volume"] = [200, { ok: true }];
            root.answers["GET /player/status"] = [200, { is_playing: true, position_ms: 1000, uri: "spotify:track:1", duration_ms: 200000 }];
            // A file first: it must stop when Spotify takes over.
            player.playTracks([{ path: root.fixtures + "/Ana Ray/Red Sky/02 Red Song 2.mp3", title: "File" }], 0, false);
            tryVerify(function() { return player.playing; }, 5000);
            player.playTracks([{ path: "spotify:track:1", title: "S", remote: true }], 0, false);
            compare(player.active.objectName, "spotifyEngine");
            verify(!findChild(player, "engineA").isPlaying);
            verify(!findChild(player, "engineB").isPlaying);
            tryVerify(function() { return root.calls.some(function(c) { return c.path === "/player/load"; }); });
            var load = root.calls.filter(function(c) { return c.path === "/player/load"; })[0];
            compare(load.body.uri, "spotify:track:1");
            verify(player.playing);
            compare(player.duration, 200000);
            // Back to a file: librespot is paused.
            root.calls = [];
            player.playTracks([{ path: root.fixtures + "/Ana Ray/Red Sky/01 Red Song 1.mp3", title: "Local" }], 0, false);
            verify(root.calls.some(function(c) { return c.path === "/player/pause"; }));
            verify(player.active.objectName === "engineA" || player.active.objectName === "engineB");
            compare(findChild(player, "spotifyEngine").path, "");
            tryVerify(function() { return player.playing; }, 5000);
        }
    }

    TestCase {
        name: "SpotifyEngine"

        function init() {
            root.calls = [];
            root.answers = {};
            endSpy.clear();
            spotify.unload();
        }

        function test_load_seek_volume() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 180000 }];
            root.answers["POST /player/seek"] = [200, { ok: true }];
            root.answers["POST /player/volume"] = [200, { ok: true }];
            spotify.load("spotify:track:x");
            spotify.seek(30000);
            spotify.play();
            var load = root.calls.filter(function(c) { return c.path === "/player/load"; })[0];
            compare(load.body.position_ms, 30000);
            verify(spotify.isPlaying);
            compare(spotify.duration, 180000);
            spotify.seek(60000);
            compare(root.calls[root.calls.length - 1].body.position_ms, 60000);
            spotify.gainFactor = 0.5;
            tryVerify(function() { return root.calls.some(function(c) { return c.path === "/player/volume" && c.body.volume === 50; }); });
        }

        function test_failed_load() {
            root.answers["POST /player/load"] = [409, { error: "librespot device not found" }];
            var reason = "";
            var onFailed = function(r) { reason = r; };
            spotify.failed.connect(onFailed);
            spotify.load("spotify:track:x");
            spotify.play();
            compare(reason, "librespot device not found");
            spotify.failed.disconnect(onFailed);
        }

        function test_end_of_track() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 10000 }];
            root.answers["GET /player/status"] = [200, { is_playing: true, position_ms: 9000, uri: "spotify:track:x", duration_ms: 10000 }];
            spotify.load("spotify:track:x");
            spotify.play();
            tryVerify(function() { return spotify.position >= 9000; }, 3000);
            compare(endSpy.count, 0);
            // librespot stops at the end; the daemon never says "ended".
            root.answers["GET /player/status"] = [200, { is_playing: false, position_ms: 0, uri: "spotify:track:x", duration_ms: 10000 }];
            tryCompare(endSpy, "count", 1, 3000);
            verify(!spotify.isPlaying);
        }

        function test_pause_mid_track_is_no_end() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 200000 }];
            root.answers["POST /player/pause"] = [200, { ok: true }];
            root.answers["GET /player/status"] = [200, { is_playing: false, position_ms: 50000, uri: "spotify:track:x", duration_ms: 200000 }];
            spotify.load("spotify:track:x");
            spotify.play();
            wait(2500);
            compare(endSpy.count, 0);
            compare(spotify.position, 50000);
            verify(!spotify.isPlaying);
        }
    }
}
