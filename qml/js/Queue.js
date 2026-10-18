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
 * The play queue, as plain data the player keeps and the tests drive:
 *
 *     { items: [entry...], pos: n, shuffle: bool, repeat: "off"|"all"|"one",
 *       original: [entry...] or null }
 *
 * items are in the order they will play, and the queue page shows them in
 * that order; pos is the playing one (-1 when empty). Each entry is a copy
 * of a track with a "qid" of its own, so the same song can be queued twice
 * and still be moved or removed on its own.
 *
 * Shuffling keeps the playing track playing and puts it first, the rest in
 * random order after it, and remembers the order before ("original"), so
 * turning shuffle off puts the queue back as it was - with whatever was
 * added or removed meanwhile.
 *
 * Every function changes the state it is given and returns it; the player
 * assigns the result to its property, which is what notifies the views.
 */

var _nextQid = 1;

function create() {
    return { items: [], pos: -1, shuffle: false, repeat: "off", original: null };
}

function _entry(track) {
    var e = {};
    for (var key in track)
        e[key] = track[key];
    e.qid = _nextQid++;
    return e;
}

function _shuffled(list, random) {
    var a = list.slice();
    for (var i = a.length - 1; i > 0; i--) {
        var j = Math.floor(random() * (i + 1));
        var t = a[i];
        a[i] = a[j];
        a[j] = t;
    }
    return a;
}

function current(state) {
    return state.pos >= 0 && state.pos < state.items.length ? state.items[state.pos] : null;
}

function count(state) {
    return state.items.length;
}

/*
 * Replaces the queue with tracks, start being the index in tracks to play
 * first. With shuffle, that track goes first and the others follow in
 * random order; start -1 then picks a random first track too.
 */
function setTracks(state, tracks, start, shuffle, random) {
    random = random || Math.random;
    var entries = tracks.map(_entry);
    state.shuffle = !!shuffle;
    if (entries.length === 0) {
        state.items = [];
        state.original = null;
        state.pos = -1;
        return state;
    }
    if (start === undefined || start === null || start < 0 || start >= entries.length)
        start = state.shuffle && (start === -1) ? Math.floor(random() * entries.length) : 0;
    if (state.shuffle) {
        state.original = entries.slice();
        var first = entries[start];
        var rest = entries.slice(0, start).concat(entries.slice(start + 1));
        state.items = [first].concat(_shuffled(rest, random));
        state.pos = 0;
    } else {
        state.original = null;
        state.items = entries;
        state.pos = start;
    }
    return state;
}

/*
 * The position that plays after the current one, or -1 when the queue
 * ends there. "auto" is a track ending on its own: only then does repeat
 * one play it again - pressing Next always moves on.
 */
function nextPos(state, auto) {
    if (state.items.length === 0)
        return -1;
    if (auto && state.repeat === "one")
        return state.pos;
    if (state.pos + 1 < state.items.length)
        return state.pos + 1;
    return state.repeat === "all" ? 0 : -1;
}

/* The position Previous goes to (the player restarts the track instead
 * when it has played for more than a few seconds). */
function previousPos(state) {
    if (state.items.length === 0)
        return -1;
    if (state.pos > 0)
        return state.pos - 1;
    return state.repeat === "all" ? state.items.length - 1 : 0;
}

function jump(state, pos) {
    if (pos >= 0 && pos < state.items.length)
        state.pos = pos;
    return state;
}

/* Tracks to play straight after the current one, in their order. */
function playNext(state, tracks) {
    var entries = tracks.map(_entry);
    if (entries.length === 0)
        return state;
    var at = state.pos + 1;
    state.items = state.items.slice(0, at).concat(entries, state.items.slice(at));
    if (state.original) {
        var cur = current(state);
        var oat = cur ? _indexOfQid(state.original, cur.qid) + 1 : state.original.length;
        state.original = state.original.slice(0, oat).concat(entries, state.original.slice(oat));
    }
    if (state.pos < 0)
        state.pos = 0;
    return state;
}

/* Tracks to play after everything already queued. */
function enqueue(state, tracks) {
    var entries = tracks.map(_entry);
    if (entries.length === 0)
        return state;
    state.items = state.items.concat(entries);
    if (state.original)
        state.original = state.original.concat(entries);
    if (state.pos < 0)
        state.pos = 0;
    return state;
}

function _indexOfQid(list, qid) {
    for (var i = 0; i < list.length; i++) {
        if (list[i].qid === qid)
            return i;
    }
    return -1;
}

/* Moves the entry at from to to (positions in play order), keeping the
 * same track playing. */
function move(state, from, to) {
    var n = state.items.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from === to)
        return state;
    var items = state.items.slice();
    var moved = items.splice(from, 1)[0];
    items.splice(to, 0, moved);
    var playing = current(state);
    state.items = items;
    if (playing)
        state.pos = _indexOfQid(items, playing.qid);
    return state;
}

/*
 * Takes the entry at pos out of the queue. Removing the playing one leaves
 * pos on the entry after it (the player starts that), or on the new last
 * one when it was the last.
 */
function removeAt(state, pos) {
    var n = state.items.length;
    if (pos < 0 || pos >= n)
        return state;
    var removed = state.items[pos];
    var items = state.items.slice();
    items.splice(pos, 1);
    state.items = items;
    if (state.original) {
        var oi = _indexOfQid(state.original, removed.qid);
        if (oi >= 0) {
            var original = state.original.slice();
            original.splice(oi, 1);
            state.original = original;
        }
    }
    if (items.length === 0)
        state.pos = -1;
    else if (pos < state.pos)
        state.pos--;
    else if (pos === state.pos && state.pos >= items.length)
        state.pos = items.length - 1;
    return state;
}

function clear(state) {
    state.items = [];
    state.original = null;
    state.pos = -1;
    return state;
}

/* Everything after the playing track goes; the playing one stays. */
function clearUpcoming(state) {
    if (state.pos < 0)
        return state;
    var keep = state.items.slice(0, state.pos + 1);
    if (state.original) {
        var qids = {};
        keep.forEach(function(e) { qids[e.qid] = true; });
        state.original = state.original.filter(function(e) { return qids[e.qid]; });
    }
    state.items = keep;
    return state;
}

function setShuffle(state, on, random) {
    random = random || Math.random;
    on = !!on;
    if (on === state.shuffle)
        return state;
    state.shuffle = on;
    var playing = current(state);
    if (on) {
        state.original = state.items.slice();
        var others = state.items.filter(function(e) { return !playing || e.qid !== playing.qid; });
        state.items = (playing ? [playing] : []).concat(_shuffled(others, random));
        state.pos = state.items.length ? 0 : -1;
    } else {
        var inQueue = {};
        state.items.forEach(function(e) { inQueue[e.qid] = true; });
        var restored = (state.original || []).filter(function(e) { return inQueue[e.qid]; });
        var known = {};
        restored.forEach(function(e) { known[e.qid] = true; });
        state.items.forEach(function(e) {
            if (!known[e.qid])
                restored.push(e);
        });
        state.items = restored;
        state.original = null;
        state.pos = playing ? _indexOfQid(restored, playing.qid) : (restored.length ? 0 : -1);
    }
    return state;
}

function setRepeat(state, mode) {
    state.repeat = (mode === "all" || mode === "one") ? mode : "off";
    return state;
}

/* off -> all -> one -> off, as the repeat button steps. */
function nextRepeatMode(mode) {
    return mode === "off" ? "all" : (mode === "all" ? "one" : "off");
}

/* The fields of an entry worth keeping across restarts. */
var storedFields = ["path", "title", "artist", "album", "albumArtist", "genre", "duration", "track", "disc", "year",
                    // a streamed track's (js/Streaming.js)
                    "artUrl", "provider", "remote"];

function _strip(e) {
    var out = { qid: e.qid };
    storedFields.forEach(function(f) {
        if (e[f] !== undefined && e[f] !== "" && e[f] !== 0)
            out[f] = e[f];
    });
    return out;
}

/* The queue as JSON, for StateFile. */
function serialize(state, positionMs) {
    return JSON.stringify({
        version: 1,
        items: state.items.map(_strip),
        original: state.original ? state.original.map(function(e) { return e.qid; }) : null,
        pos: state.pos,
        shuffle: state.shuffle,
        repeat: state.repeat,
        position: Math.max(0, Math.round(positionMs || 0))
    });
}

/* The queue back from serialize()'s JSON, with fresh qids; null when the
 * text is not a queue. "position" is where the playing track was. */
function deserialize(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!data || data.version !== 1 || !Array.isArray(data.items))
        return null;
    var state = create();
    var byOldQid = {};
    state.items = data.items.filter(function(e) { return e && typeof e.path === "string"; }).map(function(e) {
        var oldQid = e.qid;
        var entry = _entry(e);
        byOldQid[oldQid] = entry;
        return entry;
    });
    if (Array.isArray(data.original)) {
        state.original = data.original.map(function(q) { return byOldQid[q]; }).filter(function(e) { return !!e; });
    }
    state.shuffle = !!data.shuffle && !!state.original;
    if (!state.shuffle)
        state.original = null;
    state.repeat = (data.repeat === "all" || data.repeat === "one") ? data.repeat : "off";
    state.pos = state.items.length ? Math.max(0, Math.min(state.items.length - 1, data.pos | 0)) : -1;
    state.position = Math.max(0, data.position | 0);
    return state;
}
