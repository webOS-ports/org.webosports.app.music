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

import "../../qml/js/Library.js" as Library
import "../../qml/js/Lyrics.js" as Lyrics
import "../../qml/js/Art.js" as Art

/* The library's views (qml/js/Library.js), lyrics (Lyrics.js) and the
 * cover URLs (Art.js). */
TestCase {
    name: "Library"

    // As the media indexer stores them: albumArtist is the artist when the
    // file has none, track and disc are objects, times in seconds.
    function rec(path, title, artist, album, track, disc, extra) {
        var r = { _id: "id" + path, path: path, title: title, artist: artist, albumArtist: artist,
                  album: album, genre: "Pop", track: { position: track, total: 0 },
                  disc: { position: disc, total: 0 }, duration: 0, modifiedTime: 1000 };
        for (var k in extra || {})
            r[k] = extra[k];
        return r;
    }

    function records() {
        return [
            rec("/m/Ana/Red/02.mp3", "Second", "Ana Ray", "Red Sky", 2, 0),
            rec("/m/Ana/Red/01.mp3", "First", "Ana Ray", "Red Sky", 1, 0),
            rec("/m/Blue/Deep/CD2/01.flac", "Deep 2-1", "Blue Band", "Deep Water", 1, 2, { genre: "Rock" }),
            rec("/m/Blue/Deep/CD1/01.flac", "Deep 1-1", "Blue Band", "Deep Water", 1, 1, { genre: "Rock" }),
            rec("/m/Blue/Deep/CD1/02.flac", "Deep 1-2", "Blue Band", "Deep Water", 2, 1, { genre: "Rock" }),
            rec("/m/Mix/01.ogg", "Sun 1", "Ana Ray", "Summer Mix", 1, 0, { genre: "" }),
            rec("/m/Mix/02.ogg", "Sun 2", "Cool Cats", "Summer Mix", 2, 0, { genre: "" }),
            rec("/m/Other/Red/01.mp3", "Other Red", "The Zebras", "Red Sky", 1, 0),
            rec("/m/loose.mp3", "", "", "", 0, 0, { genre: "" }),
            rec("/m/ring.ogg", "Ring", "X", "Y", 0, 0, { isRingtone: true })
        ];
    }

    function albumByTitleArtist(lib, title, artist) {
        return lib.albums.filter(function(a) { return a.title === title && a.artist === artist; })[0];
    }

    function test_normalize_fills_names() {
        var s = Library.normalize({ path: "/m/x/My Song.flac" });
        compare(s.title, "My Song");
        compare(s.artist, Library.unknownArtist);
        compare(s.album, Library.unknownAlbum);
        compare(s.genre, Library.unknownGenre);
        compare(Library.normalize({ path: "/a", track: 3 }).track, 3);
        // The indexer's stand-ins for missing tags count as missing.
        var u = Library.normalize({ path: "/m/x/Voice 12.m4a", title: "Unknown Title", artist: "Unknown Artist",
                                    albumArtist: "Unknown Artist", album: "Unknown Album" });
        compare(u.title, "Voice 12");
        compare(u.albumArtist, "");
        compare(Library.normalize({ path: "/a", track: { position: 4 } }).track, 4);
    }

    function test_ringtones_and_duplicates_left_out() {
        var r = records();
        r.push(rec("/m/Ana/Red/01.mp3", "First", "Ana Ray", "Red Sky", 1, 0));
        r.push(rec("/media/internal/ringtones/ring.mp3", "Ring", "", "", 0, 0));
        r.push(rec("/media/internal/Notifications/ping.ogg", "Ping", "", "", 0, 0));
        r.push(rec("/media/internal/.cache/x.mp3", "Hidden", "", "", 0, 0));
        var lib = Library.build(r);
        compare(lib.songs.length, 9);
        verify(!lib.byPath["/m/ring.ogg"]);
        verify(Library.isSystemSound("/media/internal/Alarms/a.mp3"));
        verify(!Library.isSystemSound("/media/internal/Music/Notifications Of Love/a.mp3"));
    }

    function test_disc_folders_make_one_album() {
        var lib = Library.build(records());
        var deep = albumByTitleArtist(lib, "Deep Water", "Blue Band");
        verify(deep);
        compare(deep.tracks.map(function(t) { return t.title; }), ["Deep 1-1", "Deep 1-2", "Deep 2-1"]);
        compare(deep.discs, 2);
    }

    function test_compilation_is_various_artists() {
        var lib = Library.build(records());
        var mix = albumByTitleArtist(lib, "Summer Mix", Library.variousArtists);
        verify(mix);
        verify(mix.compilation);
        compare(mix.tracks.length, 2);
    }

    function test_same_title_other_folder_is_other_album() {
        var lib = Library.build(records());
        verify(albumByTitleArtist(lib, "Red Sky", "Ana Ray"));
        verify(albumByTitleArtist(lib, "Red Sky", "The Zebras"));
        compare(albumByTitleArtist(lib, "Red Sky", "Ana Ray").tracks[0].title, "First");
    }

    function test_tagged_album_artist_wins() {
        var r = records();
        // Both mix tracks tagged with an album artist: not Various any more.
        r[5].albumArtist = "DJ Q";
        r[6].albumArtist = "DJ Q";
        var lib = Library.build(r);
        verify(albumByTitleArtist(lib, "Summer Mix", "DJ Q"));
    }

    function test_artists() {
        var lib = Library.build(records());
        var names = lib.artists.map(function(a) { return a.name; });
        // "The Zebras" sorts under Z; Unknown and Various come last.
        compare(names.slice(0, 4), ["Ana Ray", "Blue Band", "Cool Cats", "The Zebras"]);
        compare(names.slice(4).sort(), [Library.unknownArtist, Library.variousArtists].sort());
        var ana = lib.artists[0];
        compare(ana.albums.length, 1);
        // Her own songs, and the one on the compilation.
        compare(ana.songs.length, 3);
        var various = lib.artists.filter(function(a) { return a.name === Library.variousArtists; })[0];
        compare(various.songs.length, 2);
        compare(lib.artists[3].section, "Z");
    }

    function test_genres() {
        var lib = Library.build(records());
        var names = lib.genres.map(function(g) { return g.name; });
        compare(names, ["Pop", "Rock", Library.unknownGenre]);
        compare(lib.genres[1].albums.length, 1);
    }

    function test_enrich() {
        var lib = Library.build(records());
        var s = lib.byPath["/m/Ana/Red/01.mp3"];
        Library.enrich(s, { duration: 3000, year: 2019, trackGain: -1.5, composer: "" });
        compare(s.duration, 3000);
        compare(s.year, 2019);
        compare(s.trackGain, -1.5);
        verify(s.enriched);
        Library.enrich(s, { duration: 0 });
        compare(s.duration, 3000);
        lib = Library.index(lib.songs);
        compare(albumByTitleArtist(lib, "Red Sky", "Ana Ray").year, 2019);
    }

    function test_sorting() {
        var lib = Library.build(records());
        var byTitle = Library.sortSongs(lib.songs, "title").map(function(s) { return s.title; });
        compare(byTitle[0], "Deep 1-1");
        var newest = Library.sortSongs([{ title: "a", modified: 1 }, { title: "b", modified: 5 }], "added");
        compare(newest[0].title, "b");
        var albums = Library.sortAlbums(lib.albums, "artist").map(function(a) { return a.artist; });
        compare(albums[0], "Ana Ray");
        compare(Library.sortKey("The Beatles", true), "beatles");
        compare(Library.sortKey("Ébène", false), "ebene");
        compare(Library.sectionOf("10cc", true), "#");
    }

    function test_search() {
        var lib = Library.build(records());
        var r = Library.search(lib, "deep 2");
        compare(r.songs.map(function(s) { return s.title; }), ["Deep 1-2", "Deep 2-1"]);
        compare(r.albums.length, 0);
        r = Library.search(lib, "ana");
        compare(r.artists[0].name, "Ana Ray");
        verify(r.albums.length >= 1);
        compare(Library.search(lib, "   ").songs.length, 0);
        compare(Library.search(lib, "zzz").songs.length, 0);
    }

    function test_smart_playlists() {
        var lib = Library.build(records());
        var now = 100 * 24 * 3600 * 1000;
        var stats = {
            "/m/Ana/Red/01.mp3": { playCount: 5, lastPlayed: now - 1000, favorite: true },
            "/m/Ana/Red/02.mp3": { playCount: 2, lastPlayed: now - 5000 },
            "/m/Mix/01.ogg": { playCount: 4, lastPlayed: now - 90 * 24 * 3600 * 1000 }
        };
        var titles = function(list) { return list.map(function(s) { return s.title; }); };
        compare(titles(Library.smartPlaylist("favorites", lib.songs, stats, now)), ["First"]);
        compare(titles(Library.smartPlaylist("mostPlayed", lib.songs, stats, now)), ["First", "Sun 1", "Second"]);
        compare(titles(Library.smartPlaylist("recentlyPlayed", lib.songs, stats, now)), ["First", "Second", "Sun 1"]);
        compare(titles(Library.smartPlaylist("memoryLane", lib.songs, stats, now)), ["Sun 1"]);
        compare(Library.smartPlaylist("neverPlayed", lib.songs, stats, now).length, 6);
        // Nothing added lately: still the newest 25 (here all of them).
        compare(Library.smartPlaylist("recentlyAdded", lib.songs, stats, now).length, 9);
        compare(Library.smartPlaylist("bogus", lib.songs, stats, now).length, 0);
    }

    function test_formatting() {
        compare(Library.formatDuration(0), "0:00");
        compare(Library.formatDuration(65000), "1:05");
        compare(Library.formatDuration(3725000), "1:02:05");
        compare(Library.formatTotal(42 * 60000), "42 min");
        compare(Library.formatTotal(65 * 60000), "1 h 05 min");
        compare(Library.formatTotal(12000), "0:12");
        compare(Library.summary([{ duration: 60000 }]), "1 song · 1 min");
        compare(Library.summary([]), "0 songs");
        compare(Library.albumFolderOf("/m/A/B/Disc 2/x.mp3"), "/m/A/B");
        compare(Library.albumFolderOf("/m/A/B/x.mp3"), "/m/A/B");
    }

    function test_long_form() {
        verify(Library.isLongForm({ duration: 21 * 60000 }));
        verify(Library.isLongForm({ duration: 1000, genre: "Audiobook" }));
        verify(Library.isLongForm({ duration: 1000, path: "/x/book.m4b" }));
        verify(!Library.isLongForm({ duration: 4 * 60000, genre: "Pop", path: "/x.mp3" }));
        verify(!Library.isLongForm(null));
    }

    // Streamed covers shown large are asked for large, as each service names
    // its sizes (the URLs are the services' own); small ones stay thumbnails.
    function test_art_sized() {
        compare(Art.sized("https://i.scdn.co/image/ab67616d000048513cc08d0d2f337c9992c21d9c", 900),
                "https://i.scdn.co/image/ab67616d0000b2733cc08d0d2f337c9992c21d9c");
        compare(Art.sized("https://i.scdn.co/image/ab67616d00001e023cc08d0d2f337c9992c21d9c", 500),
                "https://i.scdn.co/image/ab67616d0000b2733cc08d0d2f337c9992c21d9c");
        compare(Art.sized("https://resources.tidal.com/images/cfc4e446/7acf/42ef/baeb/c70bfcf51e15/320x320.jpg", 900),
                "https://resources.tidal.com/images/cfc4e446/7acf/42ef/baeb/c70bfcf51e15/1280x1280.jpg");
        compare(Art.sized("https://resources.tidal.com/images/cfc4e446/7acf/42ef/baeb/c70bfcf51e15/320x320.jpg", 500),
                "https://resources.tidal.com/images/cfc4e446/7acf/42ef/baeb/c70bfcf51e15/640x640.jpg");
        compare(Art.sized("https://cdn-images.dzcdn.net/images/cover/39e2d76c431f5d4ec6373f793dc144e5/250x250-000000-80-0-0.jpg", 900),
                "https://cdn-images.dzcdn.net/images/cover/39e2d76c431f5d4ec6373f793dc144e5/1000x1000-000000-80-0-0.jpg");
        compare(Art.sized("https://static.qobuz.com/images/covers/15/82/0603497948215_230.jpg", 900),
                "https://static.qobuz.com/images/covers/15/82/0603497948215_600.jpg");
        compare(Art.sized("https://i1.sndcdn.com/artworks-Ivx5qvYUBfhm-0-large.jpg", 900),
                "https://i1.sndcdn.com/artworks-Ivx5qvYUBfhm-0-t500x500.jpg");
        // YouTube's large sizes are not there for every video; others unknown.
        var yt = "https://i.ytimg.com/vi/fd0uuy4mDrE/hqdefault.jpg?sqp=x";
        compare(Art.sized(yt, 900), yt);
        compare(Art.sized("https://archive.org/services/img/x", 900), "https://archive.org/services/img/x");
        // A row's cover: the thumbnail.
        compare(Art.sized("https://i1.sndcdn.com/artworks-Ivx5qvYUBfhm-0-large.jpg", 120),
                "https://i1.sndcdn.com/artworks-Ivx5qvYUBfhm-0-large.jpg");
        compare(Art.sized("", 900), "");
    }

    function test_art_source() {
        compare(Art.source("", "x"), "");
        compare(Art.source("/m/a b#1.mp3", "AC/DC"), "image://musicart/AC%2FDC/%2Fm%2Fa%20b%231.mp3");
    }

    function test_lyrics_synced() {
        var l = Lyrics.parse("[ar:Someone]\n[offset:+500]\n[00:01.00]One\n[00:03.5][00:05.25]Two <00:03.70>words\n\n[00:02.00]");
        verify(l.synced);
        compare(l.lines.map(function(x) { return x.time; }), [500, 1500, 3000, 4750]);
        compare(l.lines.map(function(x) { return x.text; }), ["One", "", "Two words", "Two words"]);
        compare(Lyrics.lineAt(l.lines, 0), -1);
        compare(Lyrics.lineAt(l.lines, 500), 0);
        compare(Lyrics.lineAt(l.lines, 3100), 2);
        compare(Lyrics.lineAt(l.lines, 99999), 3);
    }

    function test_lyrics_plain() {
        var l = Lyrics.parse("\r\n\r\nVerse one\r\n\r\nVerse two\r\n\r\n");
        verify(!l.synced);
        compare(l.lines.map(function(x) { return x.text; }), ["Verse one", "", "Verse two"]);
        compare(Lyrics.parse("").lines.length, 0);
    }

    function test_lyrics_search_title() {
        compare(Lyrics.searchTitle("Get Lucky (Official Audio)"), "Get Lucky");
        compare(Lyrics.searchTitle("One More Time [HD] (Lyrics)"), "One More Time");
        compare(Lyrics.searchTitle("Heroes - 2017 Remaster"), "Heroes");
        compare(Lyrics.searchTitle("Heroes - Remastered"), "Heroes");
        // What belongs to the song stays.
        compare(Lyrics.searchTitle("Ain\x27t It Fun (feat. Someone)"), "Ain\x27t It Fun (feat. Someone)");
        compare(Lyrics.searchTitle("Song (Live at Wembley)"), "Song (Live at Wembley)");
        compare(Lyrics.searchTitle(""), "");
    }

    // LRCLIB search results as it answers them (shortened).
    function test_lyrics_pick_online() {
        var plain = { duration: 233, plainLyrics: "Plain line", syncedLyrics: null, instrumental: false };
        var synced = { duration: 234, plainLyrics: "Plain", syncedLyrics: "[00:01.00]Timed line", instrumental: false };
        var otherCut = { duration: 410, plainLyrics: "Extended", syncedLyrics: "[00:01.00]Extended", instrumental: false };
        var instr = { duration: 233, plainLyrics: null, syncedLyrics: null, instrumental: true };
        compare(Lyrics.pickOnline([plain, synced], 233000), { text: "[00:01.00]Timed line", instrumental: false });
        compare(Lyrics.pickOnline([plain], 233000), { text: "Plain line", instrumental: false });
        // Another cut of the song (a different length) is not this one.
        compare(Lyrics.pickOnline([otherCut, plain], 233000), { text: "Plain line", instrumental: false });
        compare(Lyrics.pickOnline([otherCut], 233000), null);
        // Length not known: any will do.
        compare(Lyrics.pickOnline([otherCut], 0), { text: "[00:01.00]Extended", instrumental: false });
        compare(Lyrics.pickOnline([instr], 233000), { text: "", instrumental: true });
        compare(Lyrics.pickOnline([instr, plain], 233000), { text: "Plain line", instrumental: false });
        compare(Lyrics.pickOnline([{ duration: 233, plainLyrics: "  ", syncedLyrics: "" }], 233000), null);
        compare(Lyrics.pickOnline([], 233000), null);
        compare(Lyrics.pickOnline(null, 233000), null);
        compare(Lyrics.pickOnline({ message: "not a list" }, 233000), null);
    }
}
