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
 * Streamed tracks: the music streaming service's track objects as the
 * app's, the "<provider>:<id>" paths they play by, and which services
 * count as signed in.
 *
 * A streamed track is a track like any other - path, title, artist, album,
 * duration (ms) - with "remote" true, "provider" and "artUrl" (its cover
 * on the web). Its path is the daemon's: "youtube:<videoId>",
 * "tidal:<id>", "spotify:track:<id>"... - so it can be queued,
 * favourited and put in playlists like a file.
 */

var accountTemplatePrefix = "org.webosports.app.music.";

// Services that need no account in Accounts.
var noAccount = ["youtube"];

// Services signed in in Videos: their account there brings the server's
// music too (org.webosports.video.<id>).
var videoAccountPrefix = "org.webosports.video.";
var videoAccount = ["jellyfin", "emby", "plex"];

var _names = {
    youtube: "YouTube", spotify: "Spotify", tidal: "Tidal", deezer: "Deezer", qobuz: "Qobuz",
    apple: "Apple Music", soundcloud: "SoundCloud", jamendo: "Jamendo", archive: "Internet Archive",
    radio: "Internet Radio"
};

function displayName(id) {
    return _names[id] || (id ? id.charAt(0).toUpperCase() + id.substring(1) : "");
}

/* "spotify:track:abc" -> { provider: "spotify", id: "track:abc" }; null for
 * a file path. */
function split(path) {
    var m = /^([a-z][a-z0-9]*):(.+)$/.exec(String(path || ""));
    if (!m || m[1] === "file")
        return null;
    return { provider: m[1], id: m[2] };
}

/*
 * A web address a launch hands the app - a station's stream, or its .pls
 * or .m3u - as the path it plays by: the music streaming service's Internet
 * Radio plays "radio:u.<the address, base64url>", opening a station's
 * playlist file for its stream (radio.go). null for anything else.
 */
function webStreamPath(target) {
    var url = String(target === undefined || target === null ? "" : target);
    if (!/^https?:\/\/[^\s\/?#]+[^\s]*$/i.test(url))
        return null;
    return "radio:u." + _base64url(_utf8(url));
}

/* What a web stream is called when the launch gave no title: the last part
 * of its path, else its host. */
function webStreamTitle(url) {
    var m = /^[a-z]+:\/\/([^\/?#]+)([^?#]*)/i.exec(String(url || ""));
    if (!m)
        return "";
    var parts = m[2].split("/").filter(function(p) { return p !== ""; });
    var name = parts.length ? parts[parts.length - 1] : "";
    try {
        name = decodeURIComponent(name);
    } catch (e) {
        // Not percent-encoded after all.
    }
    return name || m[1];
}

function _utf8(s) {
    var bytes = [];
    var e = unescape(encodeURIComponent(s));
    for (var i = 0; i < e.length; i++)
        bytes.push(e.charCodeAt(i));
    return bytes;
}

var _b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

// base64url without padding, as Go's base64.RawURLEncoding.
function _base64url(bytes) {
    var out = "";
    for (var i = 0; i < bytes.length; i += 3) {
        var n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
        out += _b64.charAt((n >> 18) & 63) + _b64.charAt((n >> 12) & 63);
        if (i + 1 < bytes.length)
            out += _b64.charAt((n >> 6) & 63);
        if (i + 2 < bytes.length)
            out += _b64.charAt(n & 63);
    }
    return out;
}

function isRemote(path) {
    return split(path) !== null;
}

function isSpotify(path) {
    var s = split(path);
    return s !== null && s.provider === "spotify";
}

/* The daemon's providerTrack (provider.go) as the app's track. */
function track(t, providerName) {
    var provider = t.provider || (split(t.path) ? split(t.path).provider : "");
    return {
        path: t.path || (provider + ":" + t.id),
        title: t.title || "",
        artist: t.artist || providerName || displayName(provider),
        album: t.album || providerName || displayName(provider),
        albumArtist: "",
        genre: "",
        duration: t.duration_ms > 0 ? t.duration_ms : 0,
        // Its place on its album, from a service that says (Subsonic).
        track: t.track > 0 ? t.track : 0,
        disc: t.disc > 0 ? t.disc : 0,
        year: 0,
        artUrl: t.thumbnail || "",
        provider: provider,
        remote: true
    };
}

/* A streamed track's artist, "" when its service gave none: track() then
 * puts the service's name as artist and album. An artist whose album has
 * their name ("Tracy Chapman" by Tracy Chapman) is an artist.
 * providerName: the service's name as the daemon gave it, if known. */
function artistOf(t, providerName) {
    var artist = String(t && t.artist || "");
    if (!t || !t.remote || artist !== String(t.album || ""))
        return artist;
    var provider = t.provider || (split(t.path) ? split(t.path).provider : "");
    if (artist === displayName(provider) || (providerName && artist === providerName))
        return "";
    return artist;
}

/* A resolve's answer ({ url, format, formats }) as { format, formats }, the
 * format it plays in among the ones the track has; null when the service did
 * not say (it has no choice). */
function formats(reply) {
    if (!reply || typeof reply.format !== "string" || reply.format === "")
        return null;
    var all = Array.isArray(reply.formats) ? reply.formats.filter(function(f) {
        return typeof f === "string" && f !== "";
    }) : [];
    if (all.indexOf(reply.format) < 0)
        all.unshift(reply.format);
    return { format: reply.format, formats: all };
}

/*
 * The services to offer: those the daemon has whose account is in
 * Accounts (Music's own, or for a media server Videos'), plus the ones
 * that need none. accountTemplateIds null (Accounts could not be asked)
 * trusts the daemon's list. By name.
 */
function signedIn(daemonProviders, accountTemplateIds) {
    var out = (daemonProviders || []).filter(function(p) {
        if (!p || !p.id)
            return false;
        if (noAccount.indexOf(p.id) >= 0 || accountTemplateIds === null || accountTemplateIds === undefined)
            return true;
        if (accountTemplateIds.indexOf(accountTemplatePrefix + p.id) >= 0)
            return true;
        return videoAccount.indexOf(p.id) >= 0 && accountTemplateIds.indexOf(videoAccountPrefix + p.id) >= 0;
    }).map(function(p) { return { id: p.id, name: p.name || displayName(p.id), browse: p.browse === true }; });
    out.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1; });
    return out;
}

/* What a playlist keeps of a track: a file's path, or a streamed track's
 * path with what is needed to show it again without asking the service. */
function stored(t) {
    if (!t || !t.remote)
        return t ? t.path : "";
    return { path: t.path, title: t.title, artist: t.artist, album: t.album, duration: t.duration,
             artUrl: t.artUrl, provider: t.provider, remote: true };
}

/*
 * A service with a library to browse (the daemon's "browse": a Subsonic
 * server): its albums and artists as the app's, so the pages that show the
 * library on the device show them too. Their tracks are fetched when one is
 * opened: "tracks" starts empty, "trackCount" is what the service says.
 */
function album(a, providerName) {
    return {
        id: String(a.id || ""),
        provider: String(a.provider || ""),
        title: a.name || "",
        artist: a.artist || providerName || "",
        artistId: String(a.artist_id || ""),
        year: a.year > 0 ? a.year : 0,
        genre: "",
        artUrl: a.thumbnail || "",
        artPath: "",
        tracks: [],
        trackCount: a.tracks > 0 ? a.tracks : 0,
        remote: true
    };
}

function artist(a) {
    return {
        id: String(a.id || ""),
        provider: String(a.provider || ""),
        name: a.name || "",
        albumCount: a.albums > 0 ? a.albums : 0,
        artUrl: a.thumbnail || "",
        remote: true
    };
}

/* "2024 · 12 songs", what an album of a service says of itself. */
function albumDetail(al) {
    var parts = [];
    if (al && al.year > 0)
        parts.push(String(al.year));
    if (al && al.trackCount > 0)
        parts.push(al.trackCount + (al.trackCount === 1 ? " song" : " songs"));
    return parts.join(" · ");
}
