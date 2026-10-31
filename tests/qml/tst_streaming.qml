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
 * Connect control, its guess at the end of a track, and how far it trusts
 * the daemon's lagging play state - also as the media session sees it.
 */
Item {
    id: root
    width: 200
    height: 200

    readonly property string fixtures: String(Qt.resolvedUrl("../fixtures/music")).replace(/^file:\/\//, "")

    // The fake daemon: answers by method and path, and records the calls.
    property var calls: []
    property var answers: ({})
    // While set, a status poll is not answered but kept here, to be answered
    // later with held(code, json): a reply still on its way.
    property bool holdStatus: false
    property var held: null
    // The same for a load: its reply is kept in heldLoad.
    property bool holdLoad: false
    property var heldLoad: null
    function fakeTransport(method, url, body, done) {
        var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "");
        root.calls = root.calls.concat([{ method: method, path: path, body: body }]);
        var key = method + " " + path.replace(/\?.*$/, "");
        if (holdStatus && key === "GET /player/status") {
            root.held = done;
            return;
        }
        if (holdLoad && key === "POST /player/load") {
            root.heldLoad = done;
            return;
        }
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
        urlResolver: function(track, done, format) { store.resolve(track, done, format); }
        streamingTransport: root.fakeTransport
    }

    SpotifyEngine {
        id: spotify
        transport: root.fakeTransport
    }

    // A media session on the Spotify engine, against a fake
    // com.webos.service.mediacontroller that records what it is told.
    property var sessionCalls: []
    QtObject {
        id: fakeBus
        function subscribe(uri, args, onReply, onError) {
            onReply({ payload: JSON.stringify({ returnValue: true, subscribed: true }) });
            return { cancel: function() {} };
        }
        function call(uri, args, onReply, onError) {
            root.sessionCalls = root.sessionCalls.concat([uri.replace(/^.*\//, "")]);
            onReply({ payload: "{\"returnValue\":true}" });
        }
    }
    QtObject {
        id: spotifyPlayer
        readonly property bool playing: spotify.isPlaying
        readonly property var current: ({ title: "T", path: "spotify:track:x" })
        readonly property real duration: spotify.duration
    }
    MediaSession {
        id: spotifySession
        bus: fakeBus
        appId: "org.webosports.app.music"
        player: spotifyPlayer
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

        // The service's name standing in for an artist it did not give is no
        // artist; a self-titled album's artist is.
        function test_artist_of() {
            var none = Streaming.track({ id: "1", provider: "youtube", title: "T" }, "YouTube Music");
            compare(Streaming.artistOf(none, "YouTube Music"), "");
            compare(Streaming.artistOf(Streaming.track({ id: "2", provider: "tidal", title: "T" }), ""), "");
            var tracy = Streaming.track({ id: "3", provider: "tidal", title: "Fast Car", artist: "Tracy Chapman",
                                          album: "Tracy Chapman" }, "Tidal");
            compare(Streaming.artistOf(tracy, "Tidal"), "Tracy Chapman");
            compare(Streaming.artistOf({ path: "/m/a.mp3", artist: "X", album: "X" }, ""), "X");
            compare(Streaming.artistOf(null, ""), "");
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

        function test_formats() {
            compare(Streaming.formats(null), null);
            compare(Streaming.formats({ url: "u" }), null);
            compare(Streaming.formats({ url: "u", format: "" }), null);
            compare(Streaming.formats({ url: "u", format: "AAC 160", formats: ["AAC 160", "AAC 96"] }),
                    { format: "AAC 160", formats: ["AAC 160", "AAC 96"] });
            // The one playing is always among them; junk is left out.
            compare(Streaming.formats({ url: "u", format: "MP3 128", formats: ["AAC 96", "", 7] }),
                    { format: "MP3 128", formats: ["MP3 128", "AAC 96"] });
            compare(Streaming.formats({ url: "u", format: "OPUS 160" }),
                    { format: "OPUS 160", formats: ["OPUS 160"] });
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

        // The user's playlists on the services that have any, asked once per
        // refresh; a playlist's tracks become the app's tracks.
        function test_service_playlists() {
            root.answers["GET /providers"] = [200, { providers: [{ id: "spotify", name: "Spotify" }, { id: "jamendo", name: "Jamendo" }] }];
            root.answers["GET /provider/spotify/playlists"] = [200, { playlists: [
                { id: "p1", name: "Road", owner: "me", thumbnail: "https://i/1", tracks: 2 },
                { name: "no id" }] }];
            root.answers["GET /provider/jamendo/playlists"] = [409, { error: "jamendo has no playlists to share" }];
            root.answers["GET /provider/spotify/playlist"] = function(body, path) {
                verify(path.indexOf("id=p1") > 0, path);
                return [200, { tracks: [{ id: "t1", provider: "spotify", title: "One", artist: "A", album: "Al",
                                          duration_ms: 61000, path: "spotify:track:t1", thumbnail: "https://i/t" }] }];
            };
            store.refresh();
            tryVerify(function() { return store.servicePlaylists.length === 1; });
            compare(store.servicePlaylists[0].provider, "spotify");
            compare(store.servicePlaylists[0].name, "Spotify");
            compare(store.servicePlaylists[0].playlists.length, 1);
            compare(store.servicePlaylists[0].playlists[0].name, "Road");
            wait(50);
            var asked = root.calls.filter(function(c) { return c.path === "/provider/spotify/playlists"; }).length;
            compare(asked, 1);
            var got = null;
            store.playlistTracks("spotify", "p1", function(tracks, error) { got = { tracks: tracks, error: error }; });
            tryVerify(function() { return got !== null; });
            compare(got.error, "");
            compare(got.tracks.length, 1);
            compare(got.tracks[0].path, "spotify:track:t1");
            verify(got.tracks[0].remote);
            compare(got.tracks[0].duration, 61000);
            // Signed out of everything: no playlists left.
            root.answers["GET /providers"] = [200, { providers: [] }];
            store.refresh();
            tryVerify(function() { return store.servicePlaylists.length === 0; });
        }

        // The format asked for, else the service's preferred one, goes to
        // the service; the ones it has come back.
        function test_resolve_formats() {
            var asked = [];
            root.answers["POST /provider/soundcloud/resolve"] = function(body) {
                asked.push(body.format === undefined ? "none" : body.format);
                return [200, { url: "https://cdn/" + body.trackId, format: body.format || "AAC 160",
                               formats: ["AAC 160", "AAC 96"] }];
            };
            var got = null;
            store.preferredFormats = {};
            store.resolve({ path: "soundcloud:5" }, function(u, e, f) { got = f; });
            tryVerify(function() { return got !== null; });
            compare(got, { format: "AAC 160", formats: ["AAC 160", "AAC 96"] });
            store.preferredFormats = { soundcloud: "AAC 96", youtube: "OPUS 160" };
            got = null;
            store.resolve({ path: "soundcloud:5" }, function(u, e, f) { got = f; });
            tryVerify(function() { return got !== null; });
            compare(got.format, "AAC 96");
            got = null;
            store.resolve({ path: "soundcloud:5" }, function(u, e, f) { got = f; }, "AAC 160");
            tryVerify(function() { return got !== null; });
            compare(asked, ["none", "AAC 96", "AAC 160"]);
            // A service without a choice: no formats.
            root.answers["POST /provider/jamendo/resolve"] = [200, { url: "https://j/1.mp3" }];
            var done = false;
            store.resolve({ path: "jamendo:1" }, function(u, e, f) { got = f; done = true; });
            tryVerify(function() { return done; });
            compare(got, null);
            store.preferredFormats = {};
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

        // The streamed track's formats, and a switch that carries on from
        // where it was in the other format's stream.
        function test_switch_format() {
            var asked = [];
            root.answers["POST /provider/soundcloud/resolve"] = function(body) {
                var f = body.format || "AAC 160";
                asked.push(f);
                if (f === "OPUS 64")
                    return [502, { error: "soundcloud: no OPUS 64" }];
                return [200, { url: fileUrl(f === "AAC 96" ? "Various/Summer Mix/02 Cool Cats - Sun.ogg"
                                                           : "Various/Summer Mix/01 Ana Ray - Sun.ogg"),
                               format: f, formats: ["AAC 160", "AAC 96", "OPUS 64"] }];
            };
            player.playTracks([{ path: "soundcloud:7", title: "Seven", remote: true }], 0, false);
            tryVerify(function() { return player.playing && player.seekable; }, 5000);
            compare(player.currentFormat, { format: "AAC 160", formats: ["AAC 160", "AAC 96", "OPUS 64"] });
            player.pause();
            player.seek(1500);
            tryVerify(function() { return player.position >= 1500; }, 5000);

            // Paused, so only the seek to where it was can bring it there.
            var result = null;
            player.switchFormat("AAC 96", function(e) { result = e; });
            tryVerify(function() { return result !== null; }, 5000);
            compare(result, "");
            compare(asked[asked.length - 1], "AAC 96");
            compare(player.currentFormat.format, "AAC 96");
            verify(String(player.active.source).indexOf("Cool Cats") >= 0, String(player.active.source));
            tryVerify(function() { return player.seekable && player.active.position >= 1400; }, 5000);
            verify(!player.playing);

            // Playing, it plays on in the new one.
            player.play();
            result = null;
            player.switchFormat("AAC 160", function(e) { result = e; });
            tryVerify(function() { return result !== null; }, 5000);
            tryVerify(function() { return player.playing && String(player.active.source).indexOf("Ana Ray") >= 0; }, 5000);

            // Not to be had: the stream playing plays on.
            result = null;
            player.switchFormat("OPUS 64", function(e) { result = e; });
            tryVerify(function() { return result !== null; }, 5000);
            compare(result, "soundcloud: no OPUS 64");
            compare(player.currentFormat.format, "AAC 160");
            verify(player.playing);
            // Not one the track has: nothing asked.
            var n = asked.length;
            result = null;
            player.switchFormat("FLAC", function(e) { result = e; });
            compare(result, "This track has no other formats.");
            compare(asked.length, n);
            player.pause();
        }

        // A preloaded next track brings its formats along, without taking
        // the playing one's; a track of a service without a choice has none.
        function test_formats_follow_the_track() {
            root.answers["POST /provider/soundcloud/resolve"] = function(body) {
                return [200, { url: fileUrl(body.trackId === "1" ? "Various/Summer Mix/01 Ana Ray - Sun.ogg"
                                                                 : "Various/Summer Mix/02 Cool Cats - Sun.ogg"),
                               format: body.trackId === "1" ? "AAC 160" : "MP3 128",
                               formats: ["AAC 160", "MP3 128"] }];
            };
            root.answers["POST /provider/jamendo/resolve"] = [200, { url: fileUrl("Various/Summer Mix/03 Zed - Sun.ogg") }];
            player.playTracks([{ path: "soundcloud:1", title: "One", remote: true },
                               { path: "soundcloud:3", title: "Three", remote: true },
                               { path: "jamendo:2", title: "Two", remote: true }], 0, false);
            tryVerify(function() { return player.playing; }, 5000);
            // A 3 s track: the next is loaded at once.
            tryVerify(function() { return player._preloadedPos === 1 && player.standby.loaded; }, 5000);
            compare(player.currentFormat.format, "AAC 160");
            player.next();
            tryVerify(function() { return player.playing && player.active.path === "soundcloud:3"; }, 5000);
            compare(player.currentFormat.format, "MP3 128");
            player.next();
            tryVerify(function() { return player.playing && player.active.path === "jamendo:2"; }, 5000);
            compare(player.currentFormat, null);
            var r = null;
            player.switchFormat("AAC 160", function(e) { r = e; });
            compare(r, "This track has no other formats.");
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
            root.holdStatus = false;
            root.held = null;
            root.holdLoad = false;
            root.heldLoad = null;
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

        // Plays, as the daemon says, with nothing asked of it since.
        function playing() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 200000 }];
            root.answers["POST /player/pause"] = [200, { ok: true }];
            root.answers["POST /player/play"] = [200, { ok: true }];
            spotify.load("spotify:track:x");
            spotify.play();
            verify(spotify.isPlaying);
            // The daemon shows the load.
            report(true, 0);
            compare(spotify._expect, null);
        }

        function report(isPlaying, position, asked) {
            reportAs("spotify:track:x", isPlaying, position, asked);
        }

        function reportAs(uri, isPlaying, position, asked) {
            spotify._onStatus(200, { is_playing: isPlaying, position_ms: position, uri: uri,
                                     duration_ms: 200000 }, asked === undefined ? spotify._commands : asked);
        }

        function sent(path) {
            return root.calls.filter(function(c) { return c.path === path; }).length;
        }

        // Loaded and asked to play, with no report yet.
        function loading() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 200000 }];
            root.answers["POST /player/pause"] = [200, { ok: true }];
            root.answers["POST /player/play"] = [200, { ok: true }];
            spotify.load("spotify:track:x");
            spotify.play();
            verify(spotify.isPlaying);
            compare(sent("/player/load"), 1);
        }

        // 12:32:55 on mindphone: the load was answered 200, librespot never
        // loaded it, and the reports kept naming the track before. It is
        // sent once more, then the engine fails instead of showing playing.
        function test_a_load_that_does_not_show_is_sent_again_then_fails() {
            loading();
            var reason = "";
            var onFailed = function(r) { reason = r; };
            spotify.failed.connect(onFailed);
            for (var i = 0; i < spotify.checkPolls - 1; ++i)
                reportAs("spotify:track:before", true, 1000 + i);
            compare(sent("/player/load"), 1, "sent again before checkPolls reports");
            ignoreWarning("Music: Spotify did not load (it reports spotify:track:before playing 6 times); asking again");
            reportAs("spotify:track:before", true, 9000);
            compare(sent("/player/load"), 2);
            compare(root.calls.filter(function(c) { return c.path === "/player/load"; })[1].body.uri, "spotify:track:x");
            verify(spotify.isPlaying);
            for (i = 0; i < spotify.checkPolls - 1; ++i)
                reportAs("spotify:track:before", true, 10000 + i);
            compare(reason, "");
            ignoreWarning("Music: Spotify did not load when asked twice (it reports spotify:track:before playing)");
            reportAs("spotify:track:before", true, 20000);
            compare(reason, "Spotify did not start the track.");
            verify(!spotify.isPlaying);
            compare(sent("/player/load"), 2, "asked a third time");
            spotify.failed.disconnect(onFailed);
        }

        function test_a_load_that_shows_after_it_is_sent_again_plays() {
            loading();
            var reason = "";
            var onFailed = function(r) { reason = r; };
            spotify.failed.connect(onFailed);
            ignoreWarning("Music: Spotify did not load (it reports no track paused 6 times); asking again");
            for (var i = 0; i < spotify.checkPolls; ++i)
                spotify._onStatus(200, { is_playing: false, position_ms: 0 }, spotify._commands);
            compare(sent("/player/load"), 2);
            report(true, 3000);
            compare(spotify._expect, null);
            verify(spotify.isPlaying);
            compare(spotify.position, 3000);
            compare(reason, "");
            spotify.failed.disconnect(onFailed);
        }

        // A second load that is answered "no" fails the engine.
        function test_a_load_sent_again_and_refused_fails() {
            loading();
            var reason = "";
            var onFailed = function(r) { reason = r; };
            spotify.failed.connect(onFailed);
            root.answers["POST /player/load"] = [409, { error: "librespot device not found" }];
            ignoreWarning("Music: Spotify did not load (it reports spotify:track:before playing 6 times); asking again");
            for (var i = 0; i < spotify.checkPolls; ++i)
                reportAs("spotify:track:before", true, 1000);
            compare(reason, "librespot device not found");
            verify(!spotify.isPlaying);
            compare(spotify._expect, null);
            spotify.failed.disconnect(onFailed);
        }

        // 12:32:47: a play answered 200 that did not reach librespot.
        function test_a_play_that_does_not_show_is_sent_again_then_taken() {
            playing();
            spotify.pause();
            report(false, 40000);
            compare(spotify._expect, null);
            spotify.play();
            compare(sent("/player/play"), 1);
            for (var i = 0; i < spotify.checkPolls - 1; ++i)
                report(false, 40000);
            verify(spotify.isPlaying, "a lagging report was taken");
            var before = spotify._commands;
            ignoreWarning("Music: Spotify did not play (it reports spotify:track:x paused 6 times); asking again");
            report(false, 40000);
            compare(sent("/player/play"), 2);
            // Replies to polls sent before the second play are about before it.
            for (i = 0; i < spotify.checkPolls; ++i)
                report(false, 40000, before);
            verify(spotify._expect !== null, "reports from before the second play counted");
            for (i = 0; i < spotify.checkPolls - 1; ++i)
                report(false, 40000);
            verify(spotify.isPlaying);
            ignoreWarning("Music: Spotify did not play when asked twice (it reports spotify:track:x paused)");
            report(false, 40000);
            verify(!spotify.isPlaying, "the paused report was not taken");
            compare(sent("/player/play"), 2);
        }

        // 12:37:15: a pause answered 200 and the music played on.
        function test_a_pause_that_does_not_show_is_sent_again_then_taken() {
            playing();
            root.calls = [];
            spotify.pause();
            compare(sent("/player/pause"), 1);
            for (var i = 0; i < spotify.checkPolls - 1; ++i)
                report(true, 40000 + i * 1000);
            verify(!spotify.isPlaying);
            ignoreWarning("Music: Spotify did not pause (it reports spotify:track:x playing 6 times); asking again");
            report(true, 46000);
            compare(sent("/player/pause"), 2);
            for (i = 0; i < spotify.checkPolls - 1; ++i)
                report(true, 47000 + i * 1000);
            verify(!spotify.isPlaying);
            ignoreWarning("Music: Spotify did not pause when asked twice (it reports spotify:track:x playing)");
            report(true, 52000);
            verify(spotify.isPlaying, "the playing report was not taken");
            compare(spotify.position, 52000);
        }

        // 12:31:13: just after a load the reports still say paused; two of
        // them used to pause it.
        function test_lagging_reports_after_a_load_are_not_taken() {
            loading();
            for (var i = 0; i < spotify.checkPolls - 1; ++i)
                report(false, 0);
            verify(spotify.isPlaying, "a lagging report after the load paused it");
            report(true, 2000);
            verify(spotify.isPlaying);
            compare(spotify._expect, null);
        }

        // The reply to a load for a track since left behind is not about
        // the track now loading.
        function test_a_reply_to_an_earlier_load_is_dropped() {
            root.answers["POST /player/play"] = [200, { ok: true }];
            root.holdLoad = true;
            spotify.load("spotify:track:a");
            spotify.play();
            var first = root.heldLoad;
            verify(first !== null, "the load was not sent");
            spotify.load("spotify:track:b");
            spotify.play();
            var second = root.heldLoad;
            verify(second !== first);
            root.holdLoad = false;
            first(200, { ok: true, duration_ms: 1000 });
            compare(spotify._expect, null, "the reply for a was taken for b");
            compare(spotify.duration, 0);
            second(200, { ok: true, duration_ms: 5000 });
            compare(spotify.duration, 5000);
            compare(spotify._expect.what, "load");
            compare(spotify._expect.body.uri, "spotify:track:b");
        }

        // A command answered other than 200 is in the journal.
        function test_a_refused_command_is_logged() {
            playing();
            root.answers["POST /player/pause"] = [503, { error: "no device" }];
            ignoreWarning("Music: Spotify /player/pause answered 503: no device");
            spotify.pause();
        }

        // The flicker: paused, and the next report still says playing.
        function test_a_stale_playing_after_a_pause_is_not_taken() {
            playing();
            spotify.pause();
            report(true, 41000);
            verify(!spotify.isPlaying, "one late report undid the pause");
            report(false, 41000);
            verify(!spotify.isPlaying);
            // Played from somewhere else after all: two reports say so.
            report(true, 42000);
            report(true, 43000);
            verify(spotify.isPlaying);
        }

        // A report on a poll sent before the pause is about before the pause.
        function test_a_report_asked_before_a_command_is_dropped() {
            playing();
            var asked = spotify._commands;
            report(true, 40000, asked);
            spotify.pause();
            var at = spotify.position;
            report(true, 99000, asked);
            report(true, 99000, asked);
            verify(!spotify.isPlaying);
            compare(spotify.position, at);
        }

        // The poll was on its way when the pause went out; its reply comes
        // after, and is about before.
        function test_a_reply_still_on_its_way_at_a_pause_is_dropped() {
            playing();
            root.holdStatus = true;
            spotify._poll();
            verify(root.held !== null, "the poll was not sent");
            var early = root.held;
            spotify.pause();
            early(200, { is_playing: true, position_ms: 99000, uri: "spotify:track:x", duration_ms: 200000 });
            spotify._poll();
            root.held(200, { is_playing: true, position_ms: 99000, uri: "spotify:track:x", duration_ms: 200000 });
            verify(!spotify.isPlaying, "a reply from before the pause counted towards undoing it");
        }

        // A command starts the count again: one stray report before it and
        // one after are not two in a row.
        function test_a_command_starts_the_count_again() {
            playing();
            report(false, 50000);
            spotify.seek(70000);
            report(false, 70000);
            verify(spotify.isPlaying, "reports either side of a seek were counted together");
        }

        // Now and then the daemon says paused for one poll mid-track.
        function test_one_paused_report_mid_track_is_not_taken() {
            playing();
            report(false, 50000);
            verify(spotify.isPlaying, "one stray report paused it");
            report(true, 51000);
            report(false, 52000);
            verify(spotify.isPlaying, "the count did not start again");
            report(false, 53000);
            verify(!spotify.isPlaying);
        }

        // What the session saw at 14:30:24: paused, activated, playing, with
        // nobody touching the player - so the keys went to it.
        function test_the_session_is_not_activated_again_by_a_stray_report() {
            playing();
            tryVerify(function() { return spotifySession.registered; });
            root.sessionCalls = [];
            report(false, 60000);
            report(true, 61000);
            compare(root.sessionCalls.filter(function(m) { return m === "activateMediaSession"; }).length, 0);
            compare(root.sessionCalls.filter(function(m) { return m === "setMediaPlayStatus"; }).length, 0);
            // A real pause and play are told, and the play activates it.
            spotify.pause();
            spotify.play();
            compare(root.sessionCalls.filter(function(m) { return m === "activateMediaSession"; }).length, 1);
        }

        function test_pause_mid_track_is_no_end() {
            root.answers["POST /player/load"] = [200, { ok: true, duration_ms: 200000 }];
            root.answers["POST /player/pause"] = [200, { ok: true }];
            root.answers["GET /player/status"] = [200, { is_playing: true, position_ms: 49000, uri: "spotify:track:x", duration_ms: 200000 }];
            spotify.load("spotify:track:x");
            spotify.play();
            tryCompare(spotify, "_expect", null, 3000);
            root.answers["GET /player/status"] = [200, { is_playing: false, position_ms: 50000, uri: "spotify:track:x", duration_ms: 200000 }];
            wait(2500);
            compare(endSpy.count, 0);
            compare(spotify.position, 50000);
            verify(!spotify.isPlaying);
        }
    }
}
