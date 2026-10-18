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

import "../../qml/js/Queue.js" as Queue

/* The play queue (qml/js/Queue.js). */
TestCase {
    name: "Queue"

    function tracks(n) {
        var out = [];
        for (var i = 0; i < n; i++)
            out.push({ path: "/m/" + i + ".mp3", title: "T" + i });
        return out;
    }

    function paths(state) {
        return state.items.map(function(e) { return e.path; });
    }

    // A fixed sequence, so shuffles can be checked.
    function seq(values) {
        var i = 0;
        return function() { return values[i++ % values.length]; };
    }

    function test_empty() {
        var q = Queue.create();
        compare(Queue.current(q), null);
        compare(Queue.nextPos(q, false), -1);
        compare(Queue.previousPos(q), -1);
        Queue.setTracks(q, [], 0, false);
        compare(q.pos, -1);
    }

    function test_set_and_step() {
        var q = Queue.setTracks(Queue.create(), tracks(3), 1, false);
        compare(q.pos, 1);
        compare(Queue.current(q).path, "/m/1.mp3");
        compare(Queue.nextPos(q, false), 2);
        q = Queue.jump(q, 2);
        compare(Queue.nextPos(q, false), -1);
        compare(Queue.previousPos(q), 1);
    }

    function test_out_of_range_start_is_first() {
        var q = Queue.setTracks(Queue.create(), tracks(3), 7, false);
        compare(q.pos, 0);
    }

    function test_repeat_modes() {
        var q = Queue.setTracks(Queue.create(), tracks(3), 2, false);
        Queue.setRepeat(q, "all");
        compare(Queue.nextPos(q, false), 0);
        Queue.jump(q, 0);
        compare(Queue.previousPos(q), 2);
        Queue.setRepeat(q, "one");
        // A track ending on its own plays again; Next moves on.
        compare(Queue.nextPos(q, true), 0);
        compare(Queue.nextPos(q, false), 1);
        Queue.setRepeat(q, "bogus");
        compare(q.repeat, "off");
        compare(Queue.nextRepeatMode("off"), "all");
        compare(Queue.nextRepeatMode("all"), "one");
        compare(Queue.nextRepeatMode("one"), "off");
    }

    function test_shuffle_keeps_chosen_first() {
        var q = Queue.setTracks(Queue.create(), tracks(5), 3, true, seq([0.0, 0.0, 0.0, 0.0]));
        compare(q.pos, 0);
        compare(Queue.current(q).path, "/m/3.mp3");
        compare(q.items.length, 5);
        var sorted = paths(q).slice().sort();
        compare(sorted, ["/m/0.mp3", "/m/1.mp3", "/m/2.mp3", "/m/3.mp3", "/m/4.mp3"]);
    }

    function test_shuffle_random_first() {
        var q = Queue.setTracks(Queue.create(), tracks(4), -1, true, seq([0.8, 0.5, 0.5, 0.5]));
        compare(Queue.current(q).path, "/m/3.mp3");
    }

    function test_unshuffle_restores_order() {
        var q = Queue.setTracks(Queue.create(), tracks(5), 0, false);
        Queue.jump(q, 2);
        Queue.setShuffle(q, true, seq([0.1, 0.9, 0.3, 0.6]));
        compare(Queue.current(q).path, "/m/2.mp3");
        compare(q.pos, 0);
        Queue.jump(q, 3);
        var playing = Queue.current(q).path;
        Queue.setShuffle(q, false);
        compare(paths(q), ["/m/0.mp3", "/m/1.mp3", "/m/2.mp3", "/m/3.mp3", "/m/4.mp3"]);
        compare(Queue.current(q).path, playing);
        compare(q.original, null);
    }

    function test_unshuffle_keeps_changes() {
        var q = Queue.setTracks(Queue.create(), tracks(3), 0, true, seq([0.5]));
        Queue.enqueue(q, [{ path: "/m/new.mp3" }]);
        Queue.removeAt(q, q.items.map(function(e) { return e.path; }).indexOf("/m/1.mp3"));
        Queue.setShuffle(q, false);
        compare(paths(q), ["/m/0.mp3", "/m/2.mp3", "/m/new.mp3"]);
    }

    function test_play_next_and_enqueue() {
        var q = Queue.setTracks(Queue.create(), tracks(3), 0, false);
        Queue.playNext(q, [{ path: "/a" }, { path: "/b" }]);
        compare(paths(q), ["/m/0.mp3", "/a", "/b", "/m/1.mp3", "/m/2.mp3"]);
        Queue.enqueue(q, [{ path: "/z" }]);
        compare(paths(q)[5], "/z");
        compare(q.pos, 0);
    }

    function test_play_next_on_empty_starts_queue() {
        var q = Queue.playNext(Queue.create(), [{ path: "/a" }]);
        compare(q.pos, 0);
        q = Queue.enqueue(Queue.create(), [{ path: "/b" }]);
        compare(q.pos, 0);
    }

    function test_same_song_twice_is_two_entries() {
        var q = Queue.setTracks(Queue.create(), [{ path: "/x" }], 0, false);
        Queue.enqueue(q, [{ path: "/x" }]);
        verify(q.items[0].qid !== q.items[1].qid);
        Queue.removeAt(q, 1);
        compare(q.items.length, 1);
        compare(q.pos, 0);
    }

    function test_move_keeps_playing_track() {
        var q = Queue.setTracks(Queue.create(), tracks(4), 1, false);
        Queue.move(q, 1, 3);
        compare(paths(q), ["/m/0.mp3", "/m/2.mp3", "/m/3.mp3", "/m/1.mp3"]);
        compare(Queue.current(q).path, "/m/1.mp3");
        Queue.move(q, 0, 2);
        compare(Queue.current(q).path, "/m/1.mp3");
        Queue.move(q, 9, 0);
        compare(q.items.length, 4);
    }

    function test_remove_positions() {
        var q = Queue.setTracks(Queue.create(), tracks(4), 2, false);
        Queue.removeAt(q, 0);
        compare(Queue.current(q).path, "/m/2.mp3");
        // Removing the playing one leaves the next in its place.
        Queue.removeAt(q, q.pos);
        compare(Queue.current(q).path, "/m/3.mp3");
        // The last one: the new last plays.
        Queue.removeAt(q, q.pos);
        compare(Queue.current(q).path, "/m/1.mp3");
        Queue.removeAt(q, 0);
        compare(q.pos, -1);
    }

    function test_clear_upcoming() {
        var q = Queue.setTracks(Queue.create(), tracks(5), 1, true, seq([0.3]));
        var playing = Queue.current(q).path;
        Queue.clearUpcoming(q);
        compare(q.items.length, 1);
        compare(Queue.current(q).path, playing);
        compare(q.original.length, 1);
        Queue.clear(q);
        compare(q.items.length, 0);
    }

    function test_serialize_round_trip() {
        var q = Queue.setTracks(Queue.create(), tracks(4), 2, true, seq([0.4, 0.7]));
        Queue.setRepeat(q, "all");
        var text = Queue.serialize(q, 12345.6);
        var r = Queue.deserialize(text);
        compare(paths(r), paths(q));
        compare(r.pos, q.pos);
        compare(r.repeat, "all");
        verify(r.shuffle);
        compare(r.position, 12346);
        // The order before shuffling survives too.
        Queue.setShuffle(r, false);
        compare(paths(r), ["/m/0.mp3", "/m/1.mp3", "/m/2.mp3", "/m/3.mp3"]);
    }

    function test_deserialize_rejects_junk() {
        compare(Queue.deserialize("not json"), null);
        compare(Queue.deserialize("{}"), null);
        compare(Queue.deserialize("{\"version\": 2, \"items\": []}"), null);
        var r = Queue.deserialize("{\"version\":1,\"items\":[{\"path\":\"/a\"},{\"nopath\":1}],\"pos\":9}");
        compare(r.items.length, 1);
        compare(r.pos, 0);
    }
}
