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
import QtMultimedia

import "../../qml"

/*
 * Player playing on after the sound server went away. All the app sees of
 * that is the engine going to Stopped (GStreamer's pulsesink error never
 * reaches QML), so the engine is stopped behind Player's back here: the
 * track must play again from where it was, a while later, until a real
 * pause, another track or five tries; and never for Spotify, whose engine
 * is Stopped only while librespot loads.
 */
Item {
    id: root
    width: 200
    height: 200

    readonly property string fixtures: String(Qt.resolvedUrl("../fixtures/music")).replace(/^file:\/\//, "")
    readonly property var sun: ({ path: root.fixtures + "/Various/Summer Mix/01 Ana Ray - Sun.ogg", title: "Sun 1" })
    readonly property var sun2: ({ path: root.fixtures + "/Various/Summer Mix/02 Cool Cats - Sun.ogg", title: "Sun 2" })

    // The music streaming service's /player/*, for Spotify.
    property var calls: []
    function fakeTransport(method, url, body, done) {
        var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "");
        root.calls = root.calls.concat([{ method: method, path: path, body: body }]);
        if (path === "/player/load")
            done(200, { ok: true, duration_ms: 200000 });
        else if (path === "/player/status")
            done(200, { is_playing: true, position_ms: 1000, uri: "spotify:track:1", duration_ms: 200000 });
        else
            done(200, { ok: true });
    }

    Player {
        id: player
        replayGain: "off"
        streamingTransport: root.fakeTransport
    }

    TestCase {
        name: "PlayerResume"
        when: windowShown

        function init() {
            player._resumeDelay = 200;
        }

        function cleanup() {
            player.pause();
            player.setRepeat("off");
        }

        // Playing sun at 1500 ms, then stopped as the sound server's loss
        // stops it.
        function playThenLose() {
            player.playTracks([root.sun], 0, false);
            tryVerify(function() { return player.playing && player.seekable; }, 5000);
            player.seek(1500);
            tryVerify(function() { return player.active.position >= 1400; }, 5000);
            player.active.stop();
            verify(!player.playing);
        }

        // From 0 it would take 1.4 s to get there.
        function verifyPlaysOnFromThere(what) {
            tryVerify(function() { return player.playing; }, 5000, what + ": playing again");
            tryVerify(function() { return player.active.position >= 1400; }, 800,
                      what + ": at " + player.active.position);
        }

        function test_plays_on_from_where_it_was() {
            playThenLose();
            wait(100);
            verify(!player.playing, "not at once");
            verifyPlaysOnFromThere("lost once");
        }

        function test_tried_again_later_and_later() {
            playThenLose();
            var lost = [Date.now()];
            for (var i = 0; i < 4; i++) {
                tryVerify(function() { return player.playing; }, 10000, "try " + (i + 1));
                lost.push(Date.now());
                // Still gone.
                player.active.stop();
            }
            // 200, 400, 800, 1600 ms apart.
            for (var j = 1; j < lost.length; j++)
                verify(lost[j] - lost[j - 1] >= 200 * Math.pow(2, j - 1) - 50,
                       "try " + j + " after " + (lost[j] - lost[j - 1]) + " ms");
            // The fifth, 3.2 s later, works.
            verifyPlaysOnFromThere("fifth try");
        }

        function test_five_tries_then_paused_there() {
            playThenLose();
            for (var i = 0; i < 5; i++) {
                tryVerify(function() { return player.playing; }, 10000, "try " + (i + 1));
                player.active.stop();
            }
            wait(200 * 32 + 500);
            verify(!player.playing, "a sixth try");
            compare(player._wantPlay, false);
            // Play goes on from there, not from 0.
            player.play();
            verifyPlaysOnFromThere("played after the tries");
        }

        // Paused, then moved to 500 ms and played: from 500 ms, the loss
        // forgotten.
        function test_a_pause_cancels() {
            playThenLose();
            player.pause();
            wait(600);
            verify(!player.playing);
            compare(player._resumeAt, -1);
            player.seek(500);
            player.play();
            tryVerify(function() { return player.playing; }, 5000);
            wait(300);
            verify(player.active.position < 1400, "at " + player.active.position);
        }

        // Another track, lost in its turn at about 300 ms: back there, not at
        // the first track's 1500 ms.
        function test_another_track_cancels() {
            playThenLose();
            player.playTracks([root.sun2], 0, false);
            tryVerify(function() { return player.playing && player.active.path === root.sun2.path; }, 5000);
            compare(player._resumeAt, -1);
            tryVerify(function() { return player.active.position >= 300; }, 5000);
            player.active.stop();
            tryVerify(function() { return player.playing; }, 5000);
            wait(300);
            verify(player.active.position < 1400, "sun 2 at " + player.active.position);
            compare(player._resumeTries, 1);
        }

        // Played again by the user while it waits: from where it was too.
        function test_play_meanwhile_plays_from_there() {
            player._resumeDelay = 5000;
            playThenLose();
            wait(100);
            player.play();
            verifyPlaysOnFromThere("played meanwhile");
        }

        // Played on and staying on for 5 s (the track repeated): lost again
        // later is a new count.
        function test_playing_on_starts_the_count_again() {
            player.setRepeat("one");
            playThenLose();
            verifyPlaysOnFromThere("first");
            wait(2500);
            verify(player._resumeAt >= 0, "settled too soon");
            tryVerify(function() { return player._resumeAt < 0; }, 4000);
            verify(player.playing);
            compare(player._resumeTries, 0);
        }

        // Repeat one: the end and the start again are no loss.
        function test_repeat_one_is_no_loss() {
            player.setRepeat("one");
            player.playTracks([root.sun], 0, false);
            tryVerify(function() { return player.playing && player.seekable; }, 5000);
            player.seek(2500);
            tryVerify(function() { return player.active.position < 1000; }, 5000);
            verify(player.playing);
            compare(player._resumeAt, -1);
        }

        function test_end_of_the_queue_is_no_loss() {
            player.playTracks([root.sun], 0, false);
            tryVerify(function() { return player.playing && player.seekable; }, 5000);
            player.seek(2500);
            tryVerify(function() { return !player.playing; }, 5000);
            wait(600);
            verify(!player.playing);
            compare(player._resumeAt, -1);
        }

        function test_not_for_spotify() {
            player.playTracks([{ path: "spotify:track:1", title: "S", remote: true }], 0, false);
            compare(player.active.objectName, "spotifyEngine");
            tryVerify(function() { return player.playing; });
            // librespot's track gone: the engine says Stopped.
            var e = player.active;
            e._loaded = false;
            e._playing = false;
            compare(e.playbackState, MediaPlayer.StoppedState);
            root.calls = [];
            wait(600);
            var sent = root.calls.filter(function(c) { return c.path !== "/player/status"; });
            compare(sent, []);
            compare(player._resumeAt, -1);
            player.playTracks([root.sun], 0, false);
        }
    }
}
