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

.import "Library.js" as Library

/*
 * Podcast episodes as the app's tracks, and what is said of them.
 *
 * An episode of the music streaming service is { id: "podcast:<f>.<e>",
 * podcast, podcastTitle, title, published, duration_ms, url, type, video,
 * description, image, position_ms, played, new, download: { state,
 * progress } }. As a track its path is its id, its artist and album the
 * podcast, and its genre "Podcast", which makes it long-form.
 */

var prefix = "podcast:";

function isEpisode(path) {
    return String(path || "").indexOf(prefix) === 0;
}

function track(e) {
    return {
        path: e.id,
        title: e.title || "",
        artist: e.podcastTitle || "",
        album: e.podcastTitle || "",
        albumArtist: "",
        genre: "Podcast",
        duration: e.duration_ms > 0 ? e.duration_ms : 0,
        track: 0,
        disc: 0,
        year: 0,
        artUrl: e.image || "",
        provider: "podcast",
        remote: true,
        video: e.video === true
    };
}

function tracks(episodes) {
    return (episodes || []).map(track);
}

var _months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/* "3 Nov", or "3 Nov 2024" for another year than nowMs's; "" unknown. */
function dateOf(ms, nowMs) {
    if (!(ms > 0))
        return "";
    var d = new Date(ms);
    var now = new Date(nowMs > 0 ? nowMs : Date.now());
    var s = d.getDate() + " " + _months[d.getMonth()];
    return d.getFullYear() === now.getFullYear() ? s : s + " " + d.getFullYear();
}

/* "12 min left", "Played", or the length. */
function progressOf(e) {
    if (e.played)
        return "Played";
    var len = e.duration_ms > 0 ? e.duration_ms : 0;
    var pos = e.position_ms > 0 ? e.position_ms : 0;
    if (pos > 0 && len > pos)
        return Library.formatTotal(len - pos) + " left";
    if (pos > 0)
        return "Started";
    return len > 0 ? Library.formatTotal(len) : "";
}

/* What a download is doing, "" when there is none. */
function downloadOf(e) {
    var d = e.download || {};
    switch (d.state) {
    case "queued":
        return "Waiting to download";
    case "downloading":
        return "Downloading " + Math.round((d.progress || 0) * 100) + "%";
    case "done":
        return "Downloaded";
    case "failed":
        return "Download failed";
    }
    return "";
}

/* The line under an episode: "3 Nov · 42 min · Downloaded". */
function detailOf(e, nowMs, withPodcast) {
    var parts = [];
    if (withPodcast && e.podcastTitle)
        parts.push(e.podcastTitle);
    var date = dateOf(e.published, nowMs);
    if (date)
        parts.push(date);
    var p = progressOf(e);
    if (p)
        parts.push(p);
    var d = downloadOf(e);
    if (d)
        parts.push(d);
    if (e.video)
        parts.push("Video");
    return parts.join(" · ");
}

/* How far an episode is, 0..1, for a bar under it. */
function fractionOf(e) {
    if (e.played || !(e.duration_ms > 0) || !(e.position_ms > 0))
        return 0;
    return Math.min(1, e.position_ms / e.duration_ms);
}

/* "3 new · 120 episodes" under a podcast. */
function podcastDetail(p) {
    var parts = [];
    if (p.newCount > 0)
        parts.push(p.newCount + " new");
    if (p.lastError)
        parts.push("Cannot be read");
    else
        parts.push(Library.plural(p.episodeCount || 0, "episode", "episodes"));
    return parts.join(" · ");
}

/* The feed address in what was typed, "" when it is a name to search for:
 * "http(s)://...", the podcast schemes some sites link with ("feed:",
 * "itpc:", "pcast:", "podcast:"), or "host.tld/path" without a scheme. */
function feedAddressOf(text) {
    var t = String(text || "").trim();
    if (t === "" || /\s/.test(t))
        return "";
    var m = /^(feed|itpcs?|pcast|podcast):(\/\/)?(.*)$/i.exec(t);
    if (m)
        t = /^https?:\/\//i.test(m[3]) ? m[3] : "https://" + m[3];
    if (/^https?:\/\/[^\/\s]+\.[^\/\s]+/i.test(t))
        return t;
    if (/^[a-z0-9-]+(\.[a-z0-9-]+)+\/\S*/i.test(t))
        return "https://" + t;
    return "";
}

/* "2 downloaded · 1 downloading" for the Downloads row. */
function downloadsDetail(episodes) {
    var done = 0, busy = 0, failed = 0;
    (episodes || []).forEach(function(e) {
        var st = (e.download || {}).state;
        if (st === "done")
            done++;
        else if (st === "queued" || st === "downloading")
            busy++;
        else if (st === "failed")
            failed++;
    });
    var parts = [];
    if (done > 0)
        parts.push(done + " downloaded");
    if (busy > 0)
        parts.push(busy + " downloading");
    if (failed > 0)
        parts.push(failed + " failed");
    return parts.join(" · ");
}

/* "Subscribed to 3 podcasts; 1 was there already; 1 cannot be read." */
function importSummary(r) {
    var added = r.added || 0, skipped = r.skipped || 0, failed = (r.failed || []).length;
    var parts = [added === 0 ? "No new podcasts" : "Subscribed to " + Library.plural(added, "podcast", "podcasts")];
    if (skipped > 0)
        parts.push(skipped + (skipped === 1 ? " was" : " were") + " there already");
    if (failed > 0)
        parts.push(failed + " cannot be read");
    return parts.join("; ") + ".";
}

/* What to say when a call failed. */
function errorOf(code, data) {
    if (data && data.error)
        return String(data.error);
    if (code === 0)
        return "The music streaming service is not running.";
    return "The music streaming service could not do that (" + code + ").";
}

/* Settings shown as choices. */
var refreshChoices = [0, 1, 3, 6, 12, 24];
var autoDownloadChoices = [0, 1, 2, 3, 5, 10];
var keepChoices = [0, 1, 3, 7, 14, 30];

function refreshLabel(h) {
    if (h === 0)
        return "Only when asked";
    return h === 1 ? "Every hour" : "Every " + h + " hours";
}

function autoDownloadLabel(n) {
    if (n === 0)
        return "Off";
    return n === 1 ? "The newest episode" : "The newest " + n;
}

function keepLabel(days) {
    if (days === 0)
        return "Keep them";
    return days === 1 ? "After a day" : "After " + days + " days";
}
