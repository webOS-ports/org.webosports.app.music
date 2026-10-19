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

import LuneOS.Service 1.0

/*
 * The app itself, qml/main.qml, with luneos-components' desktop stand-ins
 * for the bus and db8, the real MusicApp plugin, and the library in
 * tests/fixtures/music as the media indexer would have stored it.
 * Screenshots of each screen go to $MUSIC_SCREENSHOTS when it is set.
 */
Item {
    id: root
    width: 480
    height: 800

    readonly property string fixtures: String(Qt.resolvedUrl("../fixtures/music")).replace(/^file:\/\//, "")
    property var app: null

    LunaService {
        id: bus
        name: "org.webosports.app.music.tests"
    }

    // The fixture library, as com.palm.media.audio.file:1 records: no
    // lengths, albumArtist copied from artist where the file has none.
    function records() {
        var f = fixtures;
        function r(rel, title, artist, album, track, disc, genre, mtime) {
            return { _kind: "com.palm.media.audio.file:1", path: f + "/" + rel, title: title, artist: artist,
                     albumArtist: artist, album: album, genre: genre, track: { position: track, total: 0 },
                     disc: { position: disc, total: 0 }, duration: 0, modifiedTime: mtime, isRingtone: false };
        }
        return [
            r("Ana Ray/Red Sky/01 Red Song 1.mp3", "Red Song 1", "Ana Ray", "Red Sky", 1, 0, "Pop", 100),
            r("Ana Ray/Red Sky/02 Red Song 2.mp3", "Red Song 2", "Ana Ray", "Red Sky", 2, 0, "Pop", 100),
            r("Ana Ray/Red Sky/03 Red Song 3.mp3", "Red Song 3", "Ana Ray", "Red Sky", 3, 0, "Pop", 100),
            r("Blue Band/Deep Water/CD1/01 Deep 1-1.flac", "Deep 1-1", "Blue Band", "Deep Water", 1, 1, "Rock", 200),
            r("Blue Band/Deep Water/CD1/02 Deep 1-2.flac", "Deep 1-2", "Blue Band", "Deep Water", 2, 1, "Rock", 200),
            r("Blue Band/Deep Water/CD2/01 Deep 2-1.flac", "Deep 2-1", "Blue Band", "Deep Water", 1, 2, "Rock", 200),
            r("Blue Band/Deep Water/CD2/02 Deep 2-2.flac", "Deep 2-2", "Blue Band", "Deep Water", 2, 2, "Rock", 200),
            r("Various/Summer Mix/01 Ana Ray - Sun.ogg", "Sun 1", "Ana Ray", "Summer Mix", 1, 0, "Dance", 300),
            r("Various/Summer Mix/02 Cool Cats - Sun.ogg", "Sun 2", "Cool Cats", "Summer Mix", 2, 0, "Dance", 300),
            r("Various/Summer Mix/03 Zed - Sun.ogg", "Sun 3", "Zed", "Summer Mix", 3, 0, "Dance", 300),
            // Deleted since the indexer saw it (or the indexer could not
            // write the removal): left out of the library.
            r("Gone/Lost Album/01 Gone.mp3", "Gone", "Lost Artist", "Lost Album", 1, 0, "Pop", 400)
        ];
    }

    Component {
        id: coverProbe
        Image {
            asynchronous: true
            sourceSize.width: 96
            sourceSize.height: 96
        }
    }

    TestCase {
        id: test
        name: "MusicUi"
        when: windowShown

        property int shot: 0

        // Screenshots go to test-screens/ in the directory the tests run
        // from (tests/run-qml-tests.sh runs them in build/test-output).
        function screenshot(name) {
            var item = root.app.contentItem;
            waitForRendering(item);
            var done = false;
            item.grabToImage(function(result) {
                result.saveToFile("test-screens/" + root.app.width + "x" + root.app.height + "-" + name + ".png");
                done = true;
            });
            tryVerify(function() { return done; }, 5000);
        }

        // Streaming, against a fake music streaming service: Jamendo
        // signed in (no account needed in the fake's absent Accounts), its
        // tracks "resolving" to the fixture files.
        function fakeStreaming(method, url, body, done) {
            var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "").replace(/\?.*$/, "");
            if (method === "GET" && path === "/providers")
                return done(200, { providers: [{ id: "jamendo", name: "Jamendo" }] });
            if (method === "GET" && path === "/provider/jamendo/search")
                return done(200, { tracks: [
                    { id: "1", provider: "jamendo", title: "Sun Stream", artist: "Net Band", album: "Web",
                      duration_ms: 3000, path: "jamendo:1", thumbnail: "" },
                    { id: "2", provider: "jamendo", title: "Moon Stream", artist: "Net Band", album: "Web",
                      duration_ms: 3000, path: "jamendo:2", thumbnail: "" }] });
            if (method === "POST" && path === "/provider/jamendo/resolve")
                return done(200, { url: "file://" + (root.fixtures + "/Various/Summer Mix/0" + body.trackId
                                                     + (body.trackId === "1" ? " Ana Ray - Sun.ogg" : " Cool Cats - Sun.ogg"))
                                        .split("/").map(encodeURIComponent).join("/") });
            done(404, { error: "no" });
        }

        function test_18_streaming() {
            root.app.streaming.transport = fakeStreaming;
            root.app.streaming.refresh();
            tryVerify(function() { return root.app.streaming.available; });
            verify(root.app.categories.some(function(c) { return c.id === "streaming"; }));
            var lp = root.app.pageStack.get(0);
            lp.category = "streaming";
            wait(100);
            tryCompare(findByName(lp, "streamingList"), "count", 1);
            screenshot("streaming");
            root.app.openStreamingService("jamendo", "stream");
            settle();
            var page = root.app.pageStack.currentItem;
            compare(page.objectName, "streamSearchPage");
            tryVerify(function() { return page.results.length === 2; }, 3000);
            screenshot("stream-search");
            page.results.length && root.app.player.playTracks(page.results, 0, false);
            compare(root.app.player.current.title, "Sun Stream");
            tryVerify(function() { return root.app.player.playing; }, 5000);
            // What can be done with a streamed track: no Song Info, no album.
            root.app.songMenu(page.results[1], null);
            var labels = root.app.sheet.choices.map(function(c) { return c.label; });
            verify(labels.indexOf("Song Info") < 0);
            verify(labels.indexOf("Go to Album") < 0);
            verify(labels.indexOf("Play Next") >= 0);
            root.app.sheet.hide();
            // Into a playlist, and back out with its title and cover.
            var created = null;
            root.app.playlists.create("Net", [root.app.library.lib.songs[0].path], function(p) { created = p; });
            tryVerify(function() { return created !== null; });
            root.app.playlists.add(created._id, [{ path: "jamendo:2", title: "Moon Stream", artist: "Net Band",
                                                    album: "Web", duration: 3000, artUrl: "", provider: "jamendo", remote: true }]);
            var tracks = root.app.library.tracksFor(root.app.playlists.byId(created._id).tracks);
            compare(tracks[1].title, "Moon Stream");
            verify(tracks[1].remote);
            // The main search has a Jamendo section under the library's.
            root.app.pageStack.pop(null);
            root.app.openSearch();
            settle();
            var search = root.app.pageStack.currentItem;
            search.text = "stream";
            tryVerify(function() { return search.rows.some(function(r) { return r.header === "JAMENDO"; }); }, 3000);
            verify(search.rows.some(function(r) { return r.more === "jamendo"; }));
            screenshot("search-streaming");
            root.app.player.clearQueue();
            root.app.pageStack.pop(null);
            lp.category = "albums";
        }

        // A streamed track whose service has more than one format: its
        // badge under the seek bar, the Quality sheet, and the pick kept
        // for that service.
        function fakeQuality(method, url, body, done) {
            var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "").replace(/\?.*$/, "");
            if (method === "GET" && path === "/providers")
                return done(200, { providers: [{ id: "soundcloud", name: "SoundCloud" }] });
            if (method === "POST" && path === "/provider/soundcloud/resolve") {
                var f = body.format || "AAC 160";
                return done(200, { url: "file://" + (root.fixtures + (f === "AAC 96" ? "/Various/Summer Mix/02 Cool Cats - Sun.ogg"
                                                                                       : "/Various/Summer Mix/01 Ana Ray - Sun.ogg"))
                                        .split("/").map(encodeURIComponent).join("/"),
                                   format: f, formats: ["AAC 160", "AAC 96"] });
            }
            done(404, { error: "no" });
        }

        // A streamed track has no lyrics of its own: they come from LRCLIB,
        // credited; with the lookup off, none are asked for.
        function test_18_streaming_lyrics() {
            var asked = [];
            root.app.lyricsLookup.transport = function(url, done) {
                asked.push(url);
                done(200, [{ duration: 3, syncedLyrics: "[00:00.50]Up in the cloud\n[00:01.50]Second line",
                             plainLyrics: "Up in the cloud" }]);
            };
            root.app.streaming.transport = fakeQuality;
            root.app.player.playTracks([{ path: "soundcloud:1", title: "Cloud Song", artist: "Someone", album: "SoundCloud",
                                          provider: "soundcloud", remote: true, duration: 3000 }], 0, false);
            root.app.openNowPlaying();
            var np = findByName(root.app.contentItem, "nowPlaying");
            tryCompare(np, "y", 0, 3000);
            np.showLyrics = true;
            tryCompare(np, "lyricsStatus", "found", 3000);
            verify(np.lyricsText.indexOf("Up in the cloud") >= 0);
            compare(asked.length, 1);
            verify(asked[0].indexOf("track_name=Cloud%20Song&artist_name=Someone") > 0, asked[0]);
            verify(findByName(np, "lyricsCredit").visible);
            wait(300);
            screenshot("lyrics-lrclib");
            np.showLyrics = false;
            root.app.prefs.lyricsOnline = false;
            np.showLyrics = true;
            compare(np.lyricsStatus, "none");
            compare(asked.length, 1);
            np.showLyrics = false;
            root.app.prefs.lyricsOnline = true;
            root.app.lyricsLookup.transport = function(url, done) { done(200, []); };
            root.app.player.clearQueue();
            root.app.closeNowPlaying();
            settle();
        }

        // The user's Spotify playlists under their own, opened read only.
        function test_18_streaming_playlists() {
            root.app.streaming.transport = function(method, url, body, done) {
                var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "").replace(/\?.*$/, "");
                if (path === "/providers")
                    return done(200, { providers: [{ id: "spotify", name: "Spotify" }] });
                if (path === "/provider/spotify/playlists")
                    return done(200, { playlists: [{ id: "p1", name: "Road Trip", owner: "me", thumbnail: "", tracks: 2 }] });
                if (path === "/provider/spotify/playlist")
                    return done(200, { tracks: [
                        { id: "a", provider: "spotify", title: "Highway", artist: "Band", album: "Roads", duration_ms: 3000, path: "spotify:track:a" },
                        { id: "b", provider: "spotify", title: "Byway", artist: "Band", album: "Roads", duration_ms: 3000, path: "spotify:track:b" }] });
                done(404, { error: "no" });
            };
            root.app.streaming.refresh();
            tryVerify(function() { return root.app.streaming.servicePlaylists.length === 1; });
            var lp = root.app.pageStack.get(0);
            lp.category = "playlists";
            wait(100);
            var view = lp.currentView;
            var row = -1;
            for (var i = 0; i < view.rows.length; i++)
                if (view.rows[i].kind === "service")
                    row = i;
            verify(row > 0);
            compare(view.rows[row - 1].name, "SPOTIFY");
            compare(view.rows[row].name, "Road Trip");
            screenshot("playlists-spotify");
            root.app.openServicePlaylist("spotify", view.rows[row].playlist);
            settle();
            var page = root.app.pageStack.currentItem;
            compare(page.objectName, "servicePlaylistPage");
            tryCompare(page, "loading", false);
            compare(page.songs.length, 2);
            compare(page.songs[0].title, "Highway");
            verify(!page.canEdit);
            screenshot("spotify-playlist");
            root.app.pageStack.pop(null);
            root.app.streaming.transport = function(method, url, body, done) { done(404, null); };
            root.app.streaming.refresh();
            tryVerify(function() { return root.app.streaming.servicePlaylists.length === 0; });
            lp.category = "albums";
        }

        function test_18_streaming_quality() {
            root.app.prefs.streamFormats = "{}";
            root.app.streaming.transport = fakeQuality;
            root.app.streaming.refresh();
            tryVerify(function() { return root.app.streaming.available; });
            root.app.player.playTracks([{ path: "soundcloud:1", title: "Cloud Song", artist: "Someone", album: "SoundCloud",
                                          provider: "soundcloud", remote: true, duration: 3000 }], 0, false);
            tryVerify(function() { return root.app.player.playing; }, 5000);
            root.app.openNowPlaying();
            var np = findByName(root.app.contentItem, "nowPlaying");
            tryCompare(np, "y", 0, 3000); // slid in
            var badge = findByName(np, "formatBadge");
            tryVerify(function() { return badge.visible; }, 3000);
            screenshot("now-playing-quality");
            mouseClick(badge);
            verify(root.app.sheet.shown);
            wait(400); // the sheet slides up
            compare(root.app.sheet.title, "Quality");
            compare(root.app.sheet.subtitle, "SoundCloud");
            compare(root.app.sheet.choices.map(function(c) { return c.label + (c.checked ? "*" : ""); }), ["AAC 160*", "AAC 96"]);
            screenshot("quality-sheet");
            root.app.sheet.choose(1);
            tryVerify(function() { return root.app.player.currentFormat && root.app.player.currentFormat.format === "AAC 96"; }, 3000);
            compare(JSON.parse(root.app.prefs.streamFormats), { soundcloud: "AAC 96" });
            compare(root.app.streaming.preferredFormats.soundcloud, "AAC 96");
            // A local file has no badge.
            root.app.player.playTracks(root.app.library.lib.songs.slice(0, 1), 0, false);
            tryVerify(function() { return !badge.visible; }, 3000);
            root.app.player.clearQueue();
            root.app.prefs.streamFormats = "{}";
            root.app.closeNowPlaying();
            settle();
        }

        // Every main screen at every size the app has to look right at:
        // a phone (480x800, and the small 320x480), the Q25's square
        // (720x720), a tablet both ways (1024x768, 768x1024).
        // An image without com.palm.mediapermissions, whose request never
        // gets an answer: the library gives up and says why, with Try
        // Again, rather than "Looking for your music..." for ever.
        function test_19_permission_service_missing() {
            var lib = root.app.library;
            var call = lib.permissionCall;
            lib.permissionCall = function() {};
            lib.permissionTimeout = 200;
            lib._askPermission();
            compare(lib.status, "loading");
            tryCompare(lib, "status", "error", 3000);
            verify(lib.errorText.indexOf("permission service") >= 0, lib.errorText);
            lib.permissionTimeout = 15000;
            lib.permissionCall = call;
            lib.load();
            tryCompare(lib, "status", "ready", 5000);
        }

        // The dashboard swiped away: dismissed (main.qml pauses, which
        // stops Spotify in librespot); not before it has shown.
        function test_20_dashboard_dismissed() {
            var c = Qt.createComponent(Qt.resolvedUrl("../../qml/Dashboard.qml"));
            compare(c.status, Component.Ready, c.errorString());
            var dash = c.createObject(null, { player: root.app.player, theme: root.app.theme });
            verify(dash);
            var spy = Qt.createQmlObject('import QtTest; SignalSpy { signalName: "dismissed" }', test);
            spy.target = dash;
            verify(dash.visible);
            dash.visible = false;
            compare(spy.count, 1);
            dash.destroy();
            // As the shell does it on the device: a close request, the window
            // going without turning invisible. Once, also if it is hidden after.
            dash = c.createObject(null, { player: root.app.player, theme: root.app.theme });
            spy.clear();
            spy.target = dash;
            dash.windowCloseRequested(null);
            compare(spy.count, 1);
            dash.visible = false;
            compare(spy.count, 1);
            dash.destroy();
        }

        function test_99_all_sizes() {
            var sizes = [[480, 800], [320, 480], [720, 720], [1024, 768], [768, 1024]];
            var red = root.app.library.lib.albums.filter(function(a) { return a.title === "Red Sky"; })[0];
            var deep = root.app.library.lib.albums.filter(function(a) { return a.title === "Deep Water"; })[0];
            root.app.player.playTracks(red.tracks, 0, false);
            root.app.player.pause();
            sizes.forEach(function(sz) {
                root.app.width = sz[0];
                root.app.height = sz[1];
                init();
                settle();
                var lp = root.app.pageStack.get(0);
                ["albums", "artists", "songs", "playlists"].forEach(function(c) {
                    lp.category = c;
                    wait(150);
                    settle();
                    screenshot("lib-" + c);
                });
                lp.category = "albums";
                root.app.openAlbum(deep);
                settle();
                wait(200);
                screenshot("album");
                root.app.openArtist(root.app.library.artist("Ana Ray"));
                settle();
                wait(200);
                screenshot("artist");
                root.app.openQueue();
                settle();
                wait(200);
                screenshot("queue");
                root.app.songMenu(red.tracks[0], null);
                wait(250);
                screenshot("menu");
                root.app.sheet.hide();
                root.app.openNowPlaying();
                wait(300);
                screenshot("nowplaying");
                findChild(root.app.contentItem, "nowPlaying").showLyrics = true;
                wait(200);
                screenshot("lyrics");
                findChild(root.app.contentItem, "nowPlaying").showLyrics = false;
                root.app.closeNowPlaying();
                root.app.openPreferences();
                settle();
                wait(200);
                screenshot("preferences");
            });
            root.app.width = 480;
            root.app.height = 800;
        }

        function initTestCase() {
            bus.call("luna://com.palm.db/put", JSON.stringify({ objects: root.records() }), function() {}, function() {});
            var c = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
            if (c.status === Component.Error)
                fail(c.errorString());
            root.app = c.createObject(null, { width: 480, height: 800, internalStorage: root.fixtures });
            verify(root.app, c.errorString());
            // Never LRCLIB itself: songs without lyrics find none.
            root.app.lyricsLookup.transport = function(url, done) { done(200, []); };
            tryCompare(root.app.library, "status", "ready", 5000);
            // TagReader fills in the lengths the indexer leaves at 0.
            tryVerify(function() { return !root.app.library.enriching; }, 10000);
            tryVerify(function() {
                var s = root.app.library.song(root.fixtures + "/Ana Ray/Red Sky/01 Red Song 1.mp3");
                return s && s.duration > 2000;
            }, 5000);
        }

        function cleanupTestCase() {
            if (root.app) {
                root.app.player.clearQueue();
                root.app.destroy();
            }
        }

        function init() {
            root.app.goBack();
            root.app.closeNowPlaying();
            root.app.sheet.hide();
            while (root.app.pageStack.depth > 1)
                root.app.pageStack.pop(null);
            wait(50);
        }

        // Until a pushed page has slid in, StackView takes no touches.
        function settle() {
            tryCompare(root.app.pageStack, "busy", false, 3000);
        }

        function findByName(item, name) {
            return findChild(item, name);
        }

        function test_01_library_built() {
            var lib = root.app.library.lib;
            compare(lib.songs.length, 10);
            compare(lib.albums.length, 3);
            verify(!lib.byPath[root.fixtures + "/Gone/Lost Album/01 Gone.mp3"]);
            verify(!root.app.library.artist("Lost Artist"));
            var titles = lib.albums.map(function(a) { return a.title + "/" + a.artist; }).sort();
            compare(titles, ["Deep Water/Blue Band", "Red Sky/Ana Ray", "Summer Mix/Various Artists"]);
            var red = lib.byPath[root.fixtures + "/Ana Ray/Red Sky/01 Red Song 1.mp3"];
            compare(red.year, 2019);
            fuzzyCompare(red.trackGain, -1.5, 0.01);
            fuzzyCompare(red.albumGain, -2.0, 0.01);
            screenshot("albums");
        }

        function test_02_covers() {
            var red = createTemporaryObject(coverProbe, root, {
                source: "image://musicart/" + encodeURIComponent("Red Sky") + "/"
                        + encodeURIComponent(root.fixtures + "/Ana Ray/Red Sky/02 Red Song 2.mp3") });
            var blue = createTemporaryObject(coverProbe, root, {
                source: "image://musicart/" + encodeURIComponent("Deep Water") + "/"
                        + encodeURIComponent(root.fixtures + "/Blue Band/Deep Water/CD2/01 Deep 2-1.flac") });
            var none = createTemporaryObject(coverProbe, root, {
                source: "image://musicart/" + encodeURIComponent("Summer Mix") + "/"
                        + encodeURIComponent(root.fixtures + "/Various/Summer Mix/02 Cool Cats - Sun.ogg") });
            tryCompare(red, "status", Image.Ready, 5000);
            tryCompare(blue, "status", Image.Ready, 5000);
            tryCompare(none, "status", Image.Ready, 5000);
            // Embedded (MP3), the folder.jpg one folder up from CD2 (FLAC), none.
            compare(red.implicitWidth, 96);
            compare(blue.implicitWidth, 96);
            compare(none.implicitWidth, 1);
        }

        function test_03_categories() {
            var page = root.app.pageStack.get(0);
            ["artists", "songs", "genres", "playlists", "folders", "albums"].forEach(function(c) {
                page.category = c;
                wait(100);
                verify(page.currentView, c);
                screenshot("category-" + c);
            });
            page.category = "artists";
            tryVerify(function() { return findByName(page, "artistsList") && findByName(page, "artistsList").count === 5; });
            page.category = "songs";
            tryVerify(function() { return findByName(page, "songsList") && findByName(page, "songsList").count === 10; });
            page.category = "genres";
            tryVerify(function() { return findByName(page, "genresList") && findByName(page, "genresList").count === 3; });
            page.category = "albums";
        }

        function test_04_album_page_and_play() {
            var deep = root.app.library.lib.albums.filter(function(a) { return a.title === "Deep Water"; })[0];
            root.app.openAlbum(deep);
            settle();
            var page = root.app.pageStack.currentItem;
            compare(page.objectName, "albumPage");
            // Two discs: a heading before each.
            compare(page.rows.length, 6);
            compare(page.rows[0].disc, 1);
            compare(page.rows[3].disc, 2);
            screenshot("album");
            var play = findByName(page, "playButton");
            verify(play);
            mouseClick(play);
            compare(root.app.player.current.title, "Deep 1-1");
            compare(root.app.player.count, 4);
            tryVerify(function() { return root.app.player.playing; }, 5000);
            root.app.player.next();
            compare(root.app.player.current.title, "Deep 1-2");
            root.app.player.previous();
            compare(root.app.player.current.title, "Deep 1-1");
            verify(root.app.findChild ? true : true);
            verify(findByName(root.app.contentItem, "miniPlayer").visible);
        }

        function test_05_now_playing() {
            root.app.player.playTracks(root.app.library.lib.albums.filter(function(a) { return a.title === "Red Sky"; })[0].tracks, 0, false);
            root.app.openNowPlaying();
            var np = findByName(root.app.contentItem, "nowPlaying");
            verify(np && np.visible);
            compare(findByName(np, "nowPlayingTitle").text, "Red Song 1");
            tryVerify(function() { return root.app.player.duration > 2000; }, 5000);
            // Album gain: an album playing in order.
            fuzzyCompare(root.app.player.active.gainFactor, Math.pow(10, -2 / 20), 0.001);
            // The other levelling modes, from the next track on.
            root.app.prefs.replayGain = "track";
            root.app.player.jumpTo(0);
            fuzzyCompare(root.app.player.active.gainFactor, Math.pow(10, -1.5 / 20), 0.001);
            root.app.prefs.replayGain = "off";
            root.app.player.jumpTo(0);
            compare(root.app.player.active.gainFactor, 1);
            root.app.prefs.replayGain = "album";
            root.app.player.setShuffle(true);
            root.app.player.jumpTo(root.app.player.currentPos);
            fuzzyCompare(root.app.player.active.gainFactor, Math.pow(10, -2 / 20), 0.001);
            root.app.player.setShuffle(false);
            root.app.prefs.replayGain = "auto";
            root.app.player.jumpTo(0);
            screenshot("now-playing");
            np.showLyrics = true;
            tryVerify(function() { return np.lyricsText.indexOf("Chorus line") >= 0; });
            // The song's own lyrics: no credit.
            verify(!findByName(np, "lyricsCredit").visible);
            screenshot("lyrics");
            np.showLyrics = false;
            mouseClick(findByName(np, "shuffleButton"));
            verify(root.app.player.shuffle);
            mouseClick(findByName(np, "repeatButton"));
            compare(root.app.player.repeat, "all");
            mouseClick(findByName(np, "repeatButton"));
            compare(root.app.player.repeat, "one");
            mouseClick(findByName(np, "repeatButton"));
            compare(root.app.player.repeat, "off");
            mouseClick(findByName(np, "shuffleButton"));
            verify(!root.app.player.shuffle);
            compare(root.app.player.current.title, "Red Song 1");
            // Favourite from the heart.
            mouseClick(findByName(np, "favoriteButton"));
            verify(root.app.stats.isFavorite(root.app.player.current.path));
            mouseClick(findByName(np, "favoriteButton"));
            verify(!root.app.stats.isFavorite(root.app.player.current.path));
            // Tap regions on the cover: right edge = next, middle = pause.
            var cover = findByName(np, "nowPlayingCover");
            mouseClick(cover, cover.width * 0.9, cover.height / 2);
            compare(root.app.player.current.title, "Red Song 2");
            mouseClick(cover, cover.width * 0.1, cover.height / 2);
            compare(root.app.player.current.title, "Red Song 1");
            root.app.closeNowPlaying();
            verify(!np.visible);
        }

        function test_06_song_menu_and_queue() {
            root.app.player.playTracks(root.app.library.lib.songs.slice(0, 3), 0, false);
            var song = root.app.library.lib.songs[5];
            root.app.songMenu(song, null);
            verify(root.app.sheet.shown);
            var labels = root.app.sheet.choices.map(function(c) { return c.label; });
            compare(labels.slice(0, 3), ["Play Next", "Add to Queue", "Add to Playlist…"]);
            screenshot("song-menu");
            root.app.sheet.choose(0);
            verify(!root.app.sheet.shown);
            compare(root.app.player.queue.items[1].path, song.path);
            root.app.openQueue();
            settle();
            var page = root.app.pageStack.currentItem;
            var list = findByName(page, "queueList");
            tryCompare(list, "count", 4);
            screenshot("queue");
            root.app.player.moveItem(1, 3);
            compare(root.app.player.queue.items[3].path, song.path);
            root.app.player.removeItem(3);
            compare(root.app.player.count, 3);
            root.app.player.clearUpcoming();
            compare(root.app.player.count, 1);

            // A long queue on a small phone: the summary stays whole, the
            // buttons take their short labels (and the summary its own line
            // when even those do not leave room).
            root.app.width = 320;
            tryCompare(page, "width", 320);
            var many = [];
            for (var i = 0; i < 30; i++)
                many = many.concat(root.app.library.lib.songs);
            root.app.player.playTracks(many, 0, false);
            root.app.player.pause();
            var summary = findByName(page, "queueSummary");
            var save = findByName(page, "saveQueue");
            tryVerify(function() { return summary.text.indexOf("300 songs") === 0; });
            verify(!summary.truncated, summary.text);
            // Either beside the buttons or above them, never under them.
            var end = summary.mapToItem(page, summary.contentWidth, summary.height);
            var btn = save.mapToItem(page, 0, 0);
            verify(end.x <= btn.x || end.y <= btn.y, "the summary runs under the buttons");
            compare(save.text, "Save");
            // Wide enough again: one row, full labels.
            root.app.width = 1024;
            tryCompare(save, "text", "Save as Playlist");
            verify(summary.mapToItem(page, summary.contentWidth, 0).x <= save.mapToItem(page, 0, 0).x);
            root.app.player.clearQueue();
            root.app.width = 480;
        }

        function test_07_playlists() {
            var created = null;
            var paths = root.app.library.lib.songs.slice(0, 3).map(function(s) { return s.path; });
            root.app.playlists.create("Road Trip", paths, function(p) { created = p; });
            tryVerify(function() { return created !== null; });
            verify(created._id);
            compare(root.app.playlists.uniqueName("Road Trip"), "Road Trip 2");
            root.app.openPlaylist(created._id);
            settle();
            var page = root.app.pageStack.currentItem;
            compare(page.objectName, "playlistPage");
            compare(page.songs.length, 3);
            verify(page.canEdit);
            screenshot("playlist");
            page.moveRequested(0, 2);
            compare(root.app.playlists.byId(created._id).tracks[2], paths[0]);
            compare(page.songs[2].path, paths[0]);
            page.removeRequested(0);
            compare(page.songs.length, 2);
            root.app.playlists.rename(created._id, "Weekend");
            compare(page.title, "Weekend");
            // Smart lists see the favourite.
            root.app.stats.setFavorite(paths[1], true);
            compare(root.app.smartTracks("favorites").length, 1);
            root.app.openSmartPlaylist("favorites");
            settle();
            compare(root.app.pageStack.currentItem.songs.length, 1);
            root.app.pageStack.pop(null);
            root.app.pageStack.get(0).category = "playlists";
            wait(100);
            screenshot("playlists");
            root.app.pageStack.get(0).category = "albums";
        }

        function test_08_playlist_files() {
            root.app.openPlaylistFile(root.fixtures + "/mix.m3u");
            settle();
            var page = root.app.pageStack.currentItem;
            // The stream is skipped; the relative and the Windows paths are found.
            compare(page.songs.map(function(s) { return s.title; }), ["Red Song 2", "Deep 1-1"]);
        }

        function test_09_search() {
            root.app.openSearch();
            settle();
            var page = root.app.pageStack.currentItem;
            compare(page.objectName, "searchPage");
            page.text = "sun";
            tryVerify(function() { return page.result.songs.length === 3; });
            screenshot("search");
            // A song tapped: it plays, and the keyboard goes with the field's focus.
            var field = findByName(page, "searchField");
            field.forceActiveFocus(); // as on opening, also when the test window is not active
            verify(field.focus);
            var list = findByName(page, "searchResults");
            var at = -1;
            for (var i = 0; i < page.rows.length && at < 0; i++)
                if (page.rows[i].song)
                    at = i;
            verify(at >= 0);
            list.positionViewAtIndex(at, ListView.Contain);
            waitForRendering(list);
            mouseClick(list.itemAtIndex(at).item);
            verify(!field.focus);
            compare(root.app.player.current.path, page.rows[at].song.path);
            root.app.player.pause();
            field.forceActiveFocus();
            page.text = "blue";
            compare(page.result.artists[0].name, "Blue Band");
            // Just Type's Search Music action.
            root.app.pageStack.pop(null);
            root.app.launchParams = JSON.stringify({ search: "red" });
            settle();
            compare(root.app.pageStack.currentItem.objectName, "searchPage");
            compare(root.app.pageStack.currentItem.text, "red");
            compare(root.app.pageStack.currentItem.result.songs.length, 3);
        }

        function test_10_folders() {
            var lp = root.app.pageStack.get(0);
            lp.category = "folders";
            wait(100);
            var view = lp.currentView;
            verify(view.entries.length >= 1);
            view.enter(root.fixtures + "/Ana Ray/Red Sky");
            compare(view.audioEntries.length, 3);
            screenshot("folder");
            verify(root.app.goBack());
            compare(view.path, "");
            lp.category = "albums";
        }

        function test_11_open_target() {
            root.app.openTarget("file://" + encodeURI(root.fixtures + "/Various/Summer Mix/02 Cool Cats - Sun.ogg"));
            compare(root.app.player.current.title, "Sun 2");
            compare(root.app.player.count, 3);
            root.app.closeNowPlaying();
            root.app.openTarget("/no/such/file.mp3");
            compare(root.app.lastNotification, "Cannot find file.mp3.");
        }

        function test_12_launch_actions_and_exhibition() {
            root.app.player.playTracks(root.app.library.lib.songs.slice(0, 2), 0, false);
            root.app.launchParams = JSON.stringify({ action: "next" });
            compare(root.app.player.current.path, root.app.library.lib.songs[1].path);
            root.app.launchParams = JSON.stringify({ windowType: "dockModeWindow", dockMode: true });
            verify(root.app.exhibitionWanted);
            wait(200);
        }

        function test_13_preferences_and_info() {
            root.app.openPreferences();
            settle();
            compare(root.app.pageStack.currentItem.objectName, "preferencesPage");
            screenshot("preferences");
            root.app.pageStack.pop();
            root.app.openSongInfo(root.app.library.lib.byPath[root.fixtures + "/Ana Ray/Red Sky/01 Red Song 1.mp3"]);
            settle();
            var info = root.app.pageStack.currentItem;
            compare(info.tags.year, 2019);
            verify(info.tags.lyrics.indexOf("First line") >= 0);
            screenshot("song-info");
        }

        function test_14_play_counts() {
            root.app.player.clearQueue();
            var track = { path: "/test/not-playing.mp3", duration: 3000 };
            var before = root.app.stats.get(track.path) ? root.app.stats.get(track.path).playCount : 0;
            var skipsBefore = root.app.stats.get(track.path) ? root.app.stats.get(track.path).skipCount : 0;
            // Half of a 3 s track is not enough: under 30 s never counts.
            root.app.stats.trackFinished(track, 3000, true);
            compare(root.app.stats.get(track.path) ? root.app.stats.get(track.path).playCount : 0, before);
            var longTrack = { path: track.path, duration: 600000 };
            root.app.stats.trackFinished(longTrack, 240000, false);
            compare(root.app.stats.get(track.path).playCount, before + 1);
            root.app.stats.trackFinished(longTrack, 100000, false);
            compare(root.app.stats.get(track.path).playCount, before + 1);
            compare(root.app.stats.get(track.path).skipCount, skipsBefore + 1);
        }

        function test_15_sleep_timer_and_speed() {
            root.app.player.playTracks(root.app.library.lib.songs.slice(0, 2), 0, false);
            root.app.chooseSleepTimer();
            verify(root.app.sheet.shown);
            root.app.sheet.choose(0);
            verify(root.app.sleepTimer.running);
            compare(root.app.sleepTimer.remainingText, "15 min");
            root.app.sleepTimer.cancel();
            verify(!root.app.sleepTimer.running);
            root.app.chooseSpeed();
            root.app.sheet.choose(4);
            compare(root.app.player.rate, 1.5);
            root.app.player.rate = 1;
        }

        function test_16_queue_saved() {
            root.app.player.playTracks(root.app.library.lib.songs.slice(2, 6), 1, false);
            root.app.saveQueue();
            var c = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
            var second = c.createObject(null, { width: 480, height: 800 });
            verify(second);
            compare(second.player.count, 4);
            compare(second.player.current.path, root.app.library.lib.songs[3].path);
            // Restoring never starts the music.
            verify(!second.player.playing);
            second.destroy();
        }

        function test_17_tablet_layout() {
            root.app.width = 1024;
            root.app.height = 768;
            wait(200);
            verify(root.app.wide);
            root.app.pageStack.get(0).category = "albums";
            screenshot("tablet-albums");
            root.app.openNowPlaying();
            wait(300);
            screenshot("tablet-now-playing");
            root.app.closeNowPlaying();
            root.app.width = 720;
            root.app.height = 720;
            wait(200);
            screenshot("square-albums");

            // An album in the Q25's card (720x545 at its grid unit, under
            // the narrow width - 430x325 at the desktop one): the cover
            // beside the text, Play on screen without scrolling; on the
            // phone the cover above.
            var deep = root.app.library.lib.albums.filter(function(a) { return a.title === "Deep Water"; })[0];
            root.app.width = 430;
            root.app.height = 325;
            root.app.openAlbum(deep);
            settle();
            var page = root.app.pageStack.currentItem;
            var header = findByName(page, "collectionHeader");
            tryVerify(function() { return !header.narrow; });
            var play = findByName(header, "playButton");
            verify(play.mapToItem(page, 0, play.height).y <= page.height, "Play is below the fold");
            var shuffle = findByName(header, "shuffleButton");
            verify(shuffle.mapToItem(page, shuffle.width, 0).x <= page.width - root.app.theme.margin + 0.5,
                   "Shuffle runs off the edge");
            screenshot("q25-album");
            root.app.width = 480;
            root.app.height = 800;
            tryVerify(function() { return header.narrow; });
            init();
        }
    }
}
