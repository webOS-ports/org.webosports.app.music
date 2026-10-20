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
 * The player as a media session of com.webos.service.mediacontroller: what
 * is sent to it, and what its key events ask of the player. The service
 * hands a session the keys of a Bluetooth headset (and audiod's pause and
 * resume around calls) for as long as it is the one activated last.
 */

var SERVICE = "luna://com.webos.service.mediacontroller/";

/* A session id of the app's own, different for each run, so a session the
 * service still remembers from a run that crashed is never taken for this
 * one. */
function sessionId(appId, now) {
    return appId + "-" + now.toString(36);
}

function registerPayload(mediaId, appId) {
    return { "mediaId": mediaId, "appId": appId, "subscribe": true };
}

/* What a key event asks of the player: "play", "pause", "next",
 * "previous", or "" for nothing. Play and pause are play and pause, never
 * a toggle: audiod sends "pause" when a call comes in and "play" when it
 * is over, and the app may already have done the same on its own. */
function actionForKey(keyEvent) {
    switch (keyEvent) {
    case "play":
        return "play";
    case "pause":
    case "stop":
        return "pause";
    case "next":
        return "next";
    case "previous":
        return "previous";
    default:
        return "";
    }
}

/* The PLAYSTATE_ the service knows the player by. */
function playStatus(playing, hasTrack) {
    if (playing)
        return "PLAYSTATE_PLAYING";
    return hasTrack ? "PLAYSTATE_PAUSED" : "PLAYSTATE_STOPPED";
}

/* The service's mediaMetaData of a track: strings, durations as text
 * (seconds), and nothing for what the track does not have. */
function metaData(track, durationMs) {
    var meta = {};
    if (!track)
        return meta;
    if (track.title)
        meta.title = String(track.title);
    if (track.artist)
        meta.artist = String(track.artist);
    if (track.album)
        meta.album = String(track.album);
    if (track.genre)
        meta.genre = String(track.genre);
    var ms = durationMs > 0 ? durationMs : (track.duration || 0);
    if (ms > 0)
        meta.totalDuration = String(Math.round(ms / 1000));
    if (track.track > 0)
        meta.trackNumber = Math.floor(track.track);
    return meta;
}

/* A reply on the session's registerMediaSession call: { registered } for
 * the first, { keyEvent } for the keys after it, { failed } when the
 * service refused or dropped the session. */
function parseReply(payload, mediaId) {
    var reply;
    try {
        reply = typeof payload === "string" ? JSON.parse(payload) : payload;
    } catch (e) {
        return { "failed": "not JSON" };
    }
    if (!reply || reply.returnValue === false)
        return { "failed": reply && reply.errorText ? reply.errorText : "refused" };
    if (reply.keyEvent !== undefined) {
        // the service sends a session only its own keys; check all the same
        if (reply.mediaId !== undefined && reply.mediaId !== mediaId)
            return {};
        return { "keyEvent": String(reply.keyEvent) };
    }
    return { "registered": reply.subscribed === true };
}
