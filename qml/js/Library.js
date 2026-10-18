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

.pragma library

/*
 * The library as the app shows it, built from the media indexer's songs:
 * albums, artists and genres, sorting, search and the automatic playlists.
 *
 * Everything is worked out here rather than read from the indexer's album
 * and artist kinds, because those split a compilation into one album per
 * artist, know nothing of discs in separate folders, and have no lengths.
 */

var unknownArtist = "Unknown Artist";
var unknownAlbum = "Unknown Album";
var unknownGenre = "Unknown Genre";
var variousArtists = "Various Artists";

function _str(v) {
    return (v === undefined || v === null) ? "" : String(v).trim();
}

// What the media indexer stores for a tag the file does not have
// (MediaFile.cc); treated as no tag, so the file name can stand in.
var _indexerPlaceholders = ["Unknown Title", "Unknown Artist", "Unknown Album", "Unknown Genre"];

function _tag(v) {
    var s = _str(v);
    return _indexerPlaceholders.indexOf(s) >= 0 ? "" : s;
}

function _num(v) {
    var n = Number(v);
    return isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function fileName(path) {
    var s = _str(path);
    var slash = s.lastIndexOf("/");
    return slash >= 0 ? s.substring(slash + 1) : s;
}

function baseName(path) {
    var name = fileName(path);
    var dot = name.lastIndexOf(".");
    return dot > 0 ? name.substring(0, dot) : name;
}

function folderOf(path) {
    var s = _str(path);
    var slash = s.lastIndexOf("/");
    return slash > 0 ? s.substring(0, slash) : "/";
}

/*
 * The folder an album lives in: a disc subfolder ("CD1", "Disc 2",
 * "disk 03") counts as its parent, so a two-disc set is one album.
 */
function albumFolderOf(path) {
    var folder = folderOf(path);
    var last = fileName(folder);
    if (/^(cd|disc|disk|vol(ume)?)[\s._-]*\d+$/i.test(last))
        return folderOf(folder);
    return folder;
}

/*
 * A song as the app keeps it, from an indexer record (com.palm.media.audio.file:1)
 * or a file the user opened: names filled in where the tags have none.
 */
function normalize(record) {
    var path = _str(record.path);
    var track = record.track;
    var disc = record.disc;
    var song = {
        id: _str(record._id),
        path: path,
        title: _tag(record.title) || baseName(path),
        artist: _tag(record.artist) || unknownArtist,
        // The indexer puts the artist here when the file has no album
        // artist; the tags (TagReader) say which it is.
        albumArtist: _tag(record.albumArtist),
        album: _tag(record.album) || unknownAlbum,
        genre: _tag(record.genre) || unknownGenre,
        track: _num(track && typeof track === "object" ? track.position : track),
        disc: _num(disc && typeof disc === "object" ? disc.position : disc),
        duration: _num(record.duration),
        // Seconds since the epoch, as the indexer stores st_mtime.
        modified: _num(record.modifiedTime !== undefined ? record.modifiedTime : record.modified),
        year: _num(record.year),
        composer: _str(record.composer)
    };
    return song;
}

/* Fills in what TagReader read (length, year, composer, album artist,
 * ReplayGain) without overwriting what the indexer had with nothing; a
 * file that is gone is marked missing. */
function enrich(song, fields) {
    if (fields.missing) {
        song.missing = true;
        return song;
    }
    if (fields.duration > 0)
        song.duration = fields.duration;
    if (fields.year > 0)
        song.year = fields.year;
    if (fields.composer)
        song.composer = fields.composer;
    if (fields.albumArtist)
        song.albumArtist = fields.albumArtist;
    ["trackGain", "albumGain", "trackPeak", "albumPeak"].forEach(function(k) {
        if (fields[k] !== undefined)
            song[k] = fields[k];
    });
    song.enriched = true;
    return song;
}

/* What lists sort by: case and accents ignored, a leading "The " or "A "
 * moved out of the way for names ("The Beatles" under B). */
function sortKey(text, ignoreArticle) {
    var s = _str(text).toLowerCase();
    if (s.normalize)
        s = s.normalize("NFD").replace(/[̀-ͯ]/g, "");
    if (ignoreArticle)
        s = s.replace(/^(the|a|an|de|het|die|der|das|le|la|les|el|los)\s+/, "");
    return s;
}

/* The fast-scroll letter for a name: A-Z, or "#" for digits and others. */
function sectionOf(text, ignoreArticle) {
    var c = sortKey(text, ignoreArticle).charAt(0).toUpperCase();
    return (c >= "A" && c <= "Z") ? c : "#";
}

function compareText(a, b) {
    return a < b ? -1 : (a > b ? 1 : 0);
}

function compareTracks(a, b) {
    return (a.disc || 1) - (b.disc || 1)
        || (a.track || 9999) - (b.track || 9999)
        || compareText(sortKey(a.title), sortKey(b.title))
        || compareText(a.path, b.path);
}

/*
 * Albums from songs: one per album name in one folder (disc folders count
 * as theirs). The album's artist is its songs' album artist; where they
 * have none and the artists differ, it is a compilation, "Various Artists".
 */
function buildAlbums(songs) {
    var byKey = {};
    var albums = [];
    songs.forEach(function(s) {
        var key = s.album.toLowerCase() + "\u001f" + albumFolderOf(s.path);
        var album = byKey[key];
        if (!album) {
            album = byKey[key] = {
                key: key, title: s.album, artist: "", year: 0, genre: s.genre,
                tracks: [], duration: 0, artPath: s.path, discs: 1,
                _albumArtists: {}, _artists: {}
            };
            albums.push(album);
        }
        album.tracks.push(s);
        album.duration += s.duration;
        if (s.year > album.year)
            album.year = s.year;
        if (s.disc > album.discs)
            album.discs = s.disc;
        if (s.albumArtist)
            album._albumArtists[s.albumArtist] = true;
        album._artists[s.artist] = true;
    });
    albums.forEach(function(album) {
        album.tracks.sort(compareTracks);
        album.artPath = album.tracks[0].path;
        var aa = Object.keys(album._albumArtists);
        var artists = Object.keys(album._artists);
        // One album artist - tagged, or the indexer's copy of the artist
        // where every track has the same one: that one. Several: a
        // compilation, unless the artists agree after all.
        if (aa.length === 1)
            album.artist = aa[0];
        else if (artists.length === 1)
            album.artist = artists[0];
        else
            album.artist = variousArtists;
        album.compilation = album.artist === variousArtists;
        album.sortTitle = sortKey(album.title, true);
        album.sortArtist = sortKey(album.artist, true);
        delete album._albumArtists;
        delete album._artists;
        album.tracks.forEach(function(t) { t.albumKey = album.key; });
    });
    return albums;
}

/*
 * Artists: everyone who has an album, by album artist (so a compilation is
 * under Various Artists, not under each of its artists), plus everyone who
 * only appears on someone else's albums, with those songs.
 */
function buildArtists(songs, albums) {
    var byName = {};
    var artists = [];
    function artist(name) {
        var key = name.toLowerCase();
        var a = byName[key];
        if (!a) {
            a = byName[key] = { name: name, albums: [], songs: [], duration: 0, artPath: "", artAlbum: "" };
            artists.push(a);
        }
        return a;
    }
    albums.forEach(function(album) {
        var a = artist(album.artist);
        a.albums.push(album);
        if (!a.artPath) {
            a.artPath = album.artPath;
            a.artAlbum = album.title;
        }
    });
    songs.forEach(function(s) {
        var a = artist(s.artist);
        a.songs.push(s);
        a.duration += s.duration;
        if (!a.artPath) {
            a.artPath = s.path;
            a.artAlbum = s.album;
        }
    });
    artists.forEach(function(a) {
        a.albums.sort(function(x, y) { return (x.year || 9999) - (y.year || 9999) || compareText(x.sortTitle, y.sortTitle); });
        a.songs.sort(function(x, y) {
            return compareText(sortKey(x.album), sortKey(y.album)) || compareTracks(x, y);
        });
        a.sortName = sortKey(a.name, true);
        a.section = sectionOf(a.name, true);
        // An album artist with no songs of their own (Various Artists) still
        // plays its albums.
        if (a.songs.length === 0) {
            a.albums.forEach(function(album) { a.songs = a.songs.concat(album.tracks); });
            a.duration = a.songs.reduce(function(t, s) { return t + s.duration; }, 0);
        }
    });
    artists.sort(function(x, y) {
        // Unknown and Various at the end, as every player has them.
        var xr = (x.name === unknownArtist || x.name === variousArtists) ? 1 : 0;
        var yr = (y.name === unknownArtist || y.name === variousArtists) ? 1 : 0;
        return xr - yr || compareText(x.sortName, y.sortName);
    });
    return artists;
}

function buildGenres(songs, albums) {
    var byName = {};
    var genres = [];
    songs.forEach(function(s) {
        var key = s.genre.toLowerCase();
        var g = byName[key];
        if (!g) {
            g = byName[key] = { name: s.genre, songs: [], albums: [], duration: 0, artPath: s.path, artAlbum: s.album };
            genres.push(g);
        }
        g.songs.push(s);
        g.duration += s.duration;
    });
    var albumByKey = {};
    albums.forEach(function(a) { albumByKey[a.key] = a; });
    genres.forEach(function(g) {
        var seen = {};
        g.songs.forEach(function(s) {
            if (s.albumKey && !seen[s.albumKey] && albumByKey[s.albumKey]) {
                seen[s.albumKey] = true;
                g.albums.push(albumByKey[s.albumKey]);
            }
        });
        g.albums.sort(function(x, y) { return compareText(x.sortTitle, y.sortTitle); });
        g.songs.sort(function(x, y) { return compareText(sortKey(x.title), sortKey(y.title)); });
    });
    genres.sort(function(x, y) {
        var xr = x.name === unknownGenre ? 1 : 0;
        var yr = y.name === unknownGenre ? 1 : 0;
        return xr - yr || compareText(sortKey(x.name), sortKey(y.name));
    });
    return genres;
}

/*
 * The system's sounds, not music: the ringtone, alarm and notification
 * folders (Android's names, which LuneOS keeps) and hidden folders. The
 * indexer stores isRingtone false for everything, so the path decides.
 */
function isSystemSound(path) {
    return /\/(ringtones|alarms|notifications|ui|\.[^\/]*)\//i.test(path || "");
}

/* Everything the views need, in one go. */
function build(records) {
    var seen = {};
    var songs = [];
    records.forEach(function(r) {
        if (!r || !r.path || seen[r.path] || r.isRingtone === true || isSystemSound(r.path))
            return;
        seen[r.path] = true;
        songs.push(normalize(r));
    });
    return index(songs);
}

/* The views over songs that are already normalized (after enrich()). */
function index(songs) {
    var albums = buildAlbums(songs);
    var byPath = {};
    songs.forEach(function(s) {
        s.sortTitle = sortKey(s.title, false);
        s.section = sectionOf(s.title, false);
        byPath[s.path] = s;
    });
    return {
        songs: sortSongs(songs, "title"),
        albums: sortAlbums(albums, "title"),
        artists: buildArtists(songs, albums),
        genres: buildGenres(songs, albums),
        byPath: byPath
    };
}

/* Songs by "title", "artist", "album", "added" (newest first), "duration"
 * or "year". */
function sortSongs(songs, by) {
    var list = songs.slice();
    var cmp;
    switch (by) {
    case "artist":
        cmp = function(a, b) { return compareText(sortKey(a.artist, true), sortKey(b.artist, true)) || compareText(sortKey(a.album), sortKey(b.album)) || compareTracks(a, b); };
        break;
    case "album":
        cmp = function(a, b) { return compareText(sortKey(a.album), sortKey(b.album)) || compareTracks(a, b); };
        break;
    case "added":
        cmp = function(a, b) { return b.modified - a.modified || compareText(a.sortTitle || "", b.sortTitle || ""); };
        break;
    case "duration":
        cmp = function(a, b) { return b.duration - a.duration; };
        break;
    case "year":
        cmp = function(a, b) { return (b.year || 0) - (a.year || 0) || compareText(sortKey(a.album), sortKey(b.album)) || compareTracks(a, b); };
        break;
    default:
        cmp = function(a, b) { return compareText(a.sortTitle || sortKey(a.title), b.sortTitle || sortKey(b.title)) || compareText(a.path, b.path); };
    }
    list.sort(cmp);
    return list;
}

/* Albums by "title", "artist", "year" (newest first) or "added". */
function sortAlbums(albums, by) {
    var list = albums.slice();
    var newest = function(a) {
        return a.tracks.reduce(function(m, t) { return Math.max(m, t.modified); }, 0);
    };
    switch (by) {
    case "artist":
        list.sort(function(a, b) { return compareText(a.sortArtist, b.sortArtist) || (a.year || 0) - (b.year || 0) || compareText(a.sortTitle, b.sortTitle); });
        break;
    case "year":
        list.sort(function(a, b) { return (b.year || 0) - (a.year || 0) || compareText(a.sortTitle, b.sortTitle); });
        break;
    case "added":
        list.sort(function(a, b) { return newest(b) - newest(a) || compareText(a.sortTitle, b.sortTitle); });
        break;
    default:
        list.sort(function(a, b) { return compareText(a.sortTitle, b.sortTitle) || compareText(a.sortArtist, b.sortArtist); });
    }
    return list;
}

/*
 * Search over the library: every word typed must appear (in any order,
 * ignoring case and accents) in the song's title, artist or album, the
 * album's title or artist, or the artist's name.
 */
function search(lib, text, limit) {
    limit = limit || 50;
    var words = sortKey(text).split(/\s+/).filter(function(w) { return w.length > 0; });
    var result = { artists: [], albums: [], songs: [] };
    if (words.length === 0 || !lib)
        return result;
    function matches(hay) {
        for (var i = 0; i < words.length; i++) {
            if (hay.indexOf(words[i]) < 0)
                return false;
        }
        return true;
    }
    for (var i = 0; i < lib.artists.length && result.artists.length < limit; i++) {
        if (matches(sortKey(lib.artists[i].name)))
            result.artists.push(lib.artists[i]);
    }
    for (var j = 0; j < lib.albums.length && result.albums.length < limit; j++) {
        var a = lib.albums[j];
        if (matches(sortKey(a.title + " " + a.artist)))
            result.albums.push(a);
    }
    for (var k = 0; k < lib.songs.length && result.songs.length < limit; k++) {
        var s = lib.songs[k];
        if (matches(sortKey(s.title + " " + s.artist + " " + s.album)))
            result.songs.push(s);
    }
    return result;
}

/*
 * The automatic playlists. stats is { path: { playCount, lastPlayed (ms),
 * favorite } }; nowMs is the time to count "recent" from.
 */
var smartPlaylists = [
    { id: "favorites", name: "Favorites" },
    { id: "recentlyAdded", name: "Recently Added" },
    { id: "recentlyPlayed", name: "Recently Played" },
    { id: "mostPlayed", name: "Most Played" },
    { id: "neverPlayed", name: "Never Played" },
    { id: "memoryLane", name: "Memory Lane" }
];

function smartPlaylist(id, songs, stats, nowMs, limit) {
    limit = limit || 100;
    stats = stats || {};
    function st(s) { return stats[s.path] || {}; }
    var list;
    switch (id) {
    case "favorites":
        list = songs.filter(function(s) { return st(s).favorite === true; });
        list.sort(function(a, b) { return compareText(sortKey(a.artist, true), sortKey(b.artist, true)) || compareText(sortKey(a.album), sortKey(b.album)) || compareTracks(a, b); });
        return list;
    case "recentlyAdded":
        // The last 30 days, newest first; never fewer than the newest 25,
        // so a library that has not changed in a while still has a list.
        var since = Math.floor(nowMs / 1000) - 30 * 24 * 3600;
        var sorted = sortSongs(songs, "added");
        list = sorted.filter(function(s) { return s.modified >= since; });
        if (list.length < 25)
            list = sorted.slice(0, 25);
        return list.slice(0, limit);
    case "recentlyPlayed":
        list = songs.filter(function(s) { return st(s).lastPlayed > 0; });
        list.sort(function(a, b) { return st(b).lastPlayed - st(a).lastPlayed; });
        return list.slice(0, limit);
    case "mostPlayed":
        list = songs.filter(function(s) { return st(s).playCount > 0; });
        list.sort(function(a, b) { return st(b).playCount - st(a).playCount || st(b).lastPlayed - st(a).lastPlayed; });
        return list.slice(0, limit);
    case "memoryLane":
        // Played often once, not for two months: Music Player Remix's
        // "Memory Lane".
        var before = nowMs - 60 * 24 * 3600 * 1000;
        list = songs.filter(function(s) { return st(s).playCount >= 3 && st(s).lastPlayed > 0 && st(s).lastPlayed < before; });
        list.sort(function(a, b) { return st(b).playCount - st(a).playCount; });
        return list.slice(0, limit);
    case "neverPlayed":
        list = songs.filter(function(s) { return !(st(s).playCount > 0); });
        return sortSongs(list, "added").slice(0, Math.max(limit, 500));
    }
    return [];
}

/* m:ss, or h:mm:ss from an hour on. */
function formatDuration(ms) {
    var total = Math.max(0, Math.floor((ms || 0) / 1000));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var ss = (s < 10 ? "0" : "") + s;
    if (h > 0)
        return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss;
    return m + ":" + ss;
}

/* "42 min", "1 h 05 min" - the length of an album or a playlist. */
function formatTotal(ms) {
    // Under a minute (a few short tracks): the seconds, not "0 min".
    if ((ms || 0) > 0 && ms < 60000)
        return formatDuration(ms);
    var minutes = Math.round((ms || 0) / 60000);
    if (minutes < 60)
        return minutes + " min";
    var h = Math.floor(minutes / 60);
    var m = minutes % 60;
    return h + " h " + (m < 10 ? "0" : "") + m + " min";
}

function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}

/* "12 songs · 48 min", for a list's header. */
function summary(songs) {
    var total = 0;
    for (var i = 0; i < songs.length; i++)
        total += songs[i].duration || 0;
    var text = plural(songs.length, "song", "songs");
    return total > 0 ? text + " · " + formatTotal(total) : text;
}

/*
 * Long tracks (an audiobook chapter, a podcast, a DJ set) carry on where
 * they were left, as the better players do; music starts from the top.
 */
function isLongForm(song) {
    if (!song)
        return false;
    if (/audio ?book|podcast|spoken|h[oö]rbuch|speech/i.test(song.genre || ""))
        return true;
    return (song.duration || 0) >= 20 * 60 * 1000 || /\.m4b$/i.test(song.path || "");
}
