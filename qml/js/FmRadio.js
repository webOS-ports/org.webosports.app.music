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
 * FM radio (org.webosports.service.fmradio): a station as a track, how it
 * reads, and the service's status as the app uses it.
 *
 * Frequencies are kHz, as on the bus: 95000 is 95.0 MHz. A station plays
 * by the path "fm:<kHz>", which Player hands to FmEngine.
 */

var SERVICE = "luna://org.webosports.service.fmradio/";
var PROVIDER = "fm";

// The band the service offers, until its status says otherwise.
var BAND = { min: 87500, max: 108000, step: 100 };

function isFm(path) {
    return /^fm:[0-9]+$/.test(String(path || ""));
}

function pathFor(khz) {
    return PROVIDER + ":" + Math.round(khz);
}

/* The station of an "fm:" path in kHz, 0 for anything else. */
function khzOf(path) {
    if (!isFm(path))
        return 0;
    return parseInt(String(path).substring(PROVIDER.length + 1), 10);
}

/* On the band's grid. */
function valid(khz, band) {
    var b = band || BAND;
    return typeof khz === "number" && khz >= b.min && khz <= b.max
           && (khz - b.min) % b.step === 0;
}

/* "95.0", "104.3": FM is always shown to the 100 kHz. */
function mhz(khz) {
    return (Math.round(khz / 100) / 10).toFixed(1);
}

function title(khz) {
    return mhz(khz) + " FM";
}

/* One channel up (dir > 0) or down from khz, round the band at its ends. */
function step(khz, dir, band) {
    var b = band || BAND;
    var next = khz + (dir < 0 ? -b.step : b.step);
    if (next > b.max)
        return b.min;
    if (next < b.min)
        return b.max;
    return next;
}

/* A station as the app's track: played by FmEngine, and "remote" so that
 * nothing reads it as a file. Titled with its name when it has one ("100%
 * NL"), else its frequency; the artist line is what it says it is playing
 * (its RadioText), else FM Radio, the service, as a streamed track's
 * (js/Streaming.js artistOf). */
function track(khz, name, text) {
    return {
        path: pathFor(khz),
        title: name ? name : title(khz),
        artist: text ? text : "FM Radio",
        album: title(khz),
        albumArtist: "",
        genre: "",
        duration: 0,
        track: 0,
        disc: 0,
        year: 0,
        artUrl: "",
        provider: PROVIDER,
        remote: true
    };
}

/*
 * The service's getStatus reply, with what a missing field means filled in:
 * a service that is not there, or one that refused, has no radio.
 */
function status(payload) {
    var s = {};
    try {
        s = typeof payload === "string" ? JSON.parse(payload) : (payload || {});
    } catch (e) {
        s = {};
    }
    var ok = s.returnValue !== false;
    var band = s.band && s.band.min > 0 && s.band.max > s.band.min && s.band.step > 0 ? s.band : BAND;
    return {
        ok: ok,
        available: ok && s.available === true,
        powered: ok && s.powered === true,
        frequency: typeof s.frequency === "number" ? s.frequency : band.min,
        busy: ok && (s.busy === "seeking" || s.busy === "scanning" || s.busy === "naming") ? s.busy : "",
        sounding: ok && s.audio === true,
        stations: Array.isArray(s.stations) ? s.stations.filter(function(k) { return valid(k, band); }) : [],
        rssi: typeof s.rssi === "number" ? s.rssi : null,
        // What the station says of itself over RDS, while it is on.
        rdsName: ok && s.powered === true ? _text(s.rds && s.rds.name, 64) : "",
        rdsText: ok && s.powered === true ? _text(s.rds && s.rds.text, 256) : "",
        // Every station's name it heard, on or looked for: { "<kHz>": name }.
        names: ok ? _names(s.names, band) : {},
        band: band,
        errorText: ok ? (s.audioError || "") : (s.errorText || "The FM radio service did not answer.")
    };
}

function _names(value, band) {
    var out = {};
    // Anything but an object (an array, a string) has only index keys, and
    // none of those is a frequency.
    for (var k in value) {
        var name = _text(value[k], 64);
        if (/^[0-9]+$/.test(k) && valid(Number(k), band) && name !== "")
            out[String(Number(k))] = name;
    }
    return out;
}

function _text(value, max) {
    return typeof value === "string" ? value.trim().slice(0, max) : "";
}

/*
 * The names of the stations, by frequency: the one the user gave it, else
 * the one it sent over RDS, else "". Both maps are { "<kHz>": name }.
 */
function nameOf(khz, own, learned) {
    var k = String(khz);
    if (own && typeof own[k] === "string" && own[k] !== "")
        return own[k];
    if (learned && typeof learned[k] === "string")
        return learned[k];
    return "";
}

/* names with khz called name: a new map, or null if it already was. An
 * empty name takes it out. */
function withName(names, khz, name) {
    var k = String(khz);
    var n = _text(name, 64);
    var cur = names && typeof names[k] === "string" ? names[k] : "";
    if (cur === n)
        return null;
    var out = {};
    for (var key in names)
        out[key] = names[key];
    if (n === "")
        delete out[k];
    else
        out[k] = n;
    return out;
}

/* A map of names from the preferences' JSON: {} for anything else. */
function namesFrom(json) {
    try {
        var o = JSON.parse(json);
        return o && typeof o === "object" && !Array.isArray(o) ? o : {};
    } catch (e) {
        return {};
    }
}

/*
 * How strong the station is, 0 - 4 bars, from the RSSI in dBm. On mindphone
 * (2026-11-06, wired headphones as the antenna) the strongest local station
 * read -67 dBm, weaker ones -80 to -84, and empty channels -88 to -92.
 */
function bars(rssi) {
    if (rssi === null || rssi === undefined)
        return 0;
    if (rssi >= -72)
        return 4;
    if (rssi >= -78)
        return 3;
    if (rssi >= -84)
        return 2;
    if (rssi >= -88)
        return 1;
    return 0;
}

/* The stations to list: the last scan's, in order of frequency, without
 * repeats. */
function stationList(stations) {
    var seen = {};
    return (stations || []).filter(function(k) {
        if (typeof k !== "number" || seen[k])
            return false;
        seen[k] = true;
        return true;
    }).sort(function(a, b) { return a - b; });
}
