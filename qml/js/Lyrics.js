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
 * Lyrics, plain or timed (LRC): "[01:23.45]A line", several time tags on one
 * line for a repeated chorus, an [offset:+250] in ms, and the word-by-word
 * <01:23.45> tags of enhanced LRC, which are dropped - the line is shown
 * whole. Metadata tags ([ar:], [ti:], [length:] ...) are skipped.
 *
 *     { synced: true, lines: [{ time: 83450, text: "A line" }, ...] }
 *
 * Plain lyrics come back as lines with time -1.
 */

var _timeTag = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

function _ms(min, sec, frac) {
    var f = 0;
    if (frac !== undefined && frac !== "") {
        // ".5" is half a second, ".45" 450 ms, ".450" 450 ms.
        f = Math.round(Number("0." + frac) * 1000);
    }
    return Number(min) * 60000 + Number(sec) * 1000 + f;
}

function parse(text) {
    var result = { synced: false, lines: [] };
    if (!text)
        return result;
    var offset = 0;
    var timed = [];
    var plain = [];
    var rows = String(text).replace(/\r\n?/g, "\n").split("\n");
    rows.forEach(function(row) {
        var off = /^\s*\[offset:\s*([+-]?\d+)\s*\]/i.exec(row);
        if (off) {
            offset = Number(off[1]);
            return;
        }
        var times = [];
        var m;
        _timeTag.lastIndex = 0;
        var rest = row;
        // The time tags lead the line; whatever follows them is the text.
        var lead = /^\s*((?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]\s*)+)(.*)$/.exec(row);
        if (lead) {
            while ((m = _timeTag.exec(lead[1])) !== null)
                times.push(_ms(m[1], m[2], m[3]));
            rest = lead[2];
        } else if (/^\s*\[[a-z#]+:[^\]]*\]\s*$/i.test(row)) {
            return; // [ar:Artist] and friends
        }
        rest = rest.replace(/<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>/g, "").replace(/\s+/g, " ").trim();
        if (times.length > 0) {
            times.forEach(function(t) { timed.push({ time: t, text: rest }); });
        } else {
            plain.push({ time: -1, text: rest });
        }
    });
    if (timed.length > 0) {
        // A positive offset shows the lyrics sooner.
        timed.forEach(function(l) { l.time = Math.max(0, l.time - offset); });
        timed.sort(function(a, b) { return a.time - b.time; });
        result.synced = true;
        result.lines = timed;
    } else {
        // Blank lines at either end say nothing; those between verses stay.
        while (plain.length && plain[0].text === "")
            plain.shift();
        while (plain.length && plain[plain.length - 1].text === "")
            plain.pop();
        result.lines = plain;
    }
    return result;
}

/* The index of the line being sung at positionMs, -1 before the first. */
function lineAt(lines, positionMs) {
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        if (lines[mid].time <= positionMs) {
            found = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    return found;
}
