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

var _names = {
    youtube: "YouTube", spotify: "Spotify", tidal: "Tidal", deezer: "Deezer", qobuz: "Qobuz",
    apple: "Apple Music", soundcloud: "SoundCloud", jamendo: "Jamendo", archive: "Internet Archive"
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
        track: 0,
        disc: 0,
        year: 0,
        artUrl: t.thumbnail || "",
        provider: provider,
        remote: true
    };
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
 * Accounts, plus the ones that need none. accountTemplateIds null (Accounts
 * could not be asked) trusts the daemon's list. By name.
 */
function signedIn(daemonProviders, accountTemplateIds) {
    var out = (daemonProviders || []).filter(function(p) {
        if (!p || !p.id)
            return false;
        if (noAccount.indexOf(p.id) >= 0 || accountTemplateIds === null || accountTemplateIds === undefined)
            return true;
        return accountTemplateIds.indexOf(accountTemplatePrefix + p.id) >= 0;
    }).map(function(p) { return { id: p.id, name: p.name || displayName(p.id) }; });
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
