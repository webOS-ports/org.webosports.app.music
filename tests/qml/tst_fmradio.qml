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
import "../../qml/js/FmRadio.js" as Fm

/*
 * FM (js/FmRadio.js, FmRadio.qml, FmEngine.qml) against a fake
 * org.webosports.service.fmradio: the status read from it, each request and
 * its answer, a service that refuses or goes, and the engine turning the
 * radio on and off as Player plays and pauses a station.
 */
Item {
    id: root
    width: 100
    height: 100

    // --- the fake service --------------------------------------------------

    property var calls: []          // { method, payload, reply, fail } of every call()
    property var subscription: null
    property int subscribes: 0
    property int cancels: 0
    // Answer calls at once, or leave them for the test to answer.
    property bool answerNow: true
    property var answers: ({})      // method -> reply payload

    function method(uri) { return uri.replace(Fm.SERVICE, ""); }

    // As LuneOS.Service before its handle is registered: every call fails
    // at once, inside call()/subscribe(), and still hands back a call.
    property bool failAtOnce: false

    QtObject {
        id: fakeBus
        signal initialized()
        function subscribe(uri, args, onReply, onError) {
            root.subscribes++;
            if (root.failAtOnce) {
                onError("Failed to call remote service: invalid handle");
                return { cancel: function() { root.cancels++; } };
            }
            var call = {
                method: root.method(uri), payload: JSON.parse(args),
                reply: function(p) { onReply({ payload: JSON.stringify(p) }); },
                fail: function(e) { onError(e); },
                cancel: function() { root.cancels++; root.subscription = null; }
            };
            root.subscription = call;
            return call;
        }
        function call(uri, args, onReply, onError) {
            var c = {
                method: root.method(uri), payload: JSON.parse(args),
                reply: function(p) { onReply({ payload: JSON.stringify(p) }); },
                fail: function(e) { onError(e); }
            };
            root.calls.push(c);
            if (root.answerNow)
                c.reply(root.answers[c.method] || { returnValue: true });
        }
    }

    function sent(name) {
        return calls.filter(function(c) { return c.method === name; });
    }

    function status(extra) {
        var s = { returnValue: true, available: true, powered: false, frequency: 95000,
                  busy: "idle", audio: false, band: { min: 87500, max: 108000, step: 100 },
                  stations: [] };
        for (var k in extra)
            s[k] = extra[k];
        return s;
    }

    Component {
        id: radioComponent
        FmRadio {
            bus: fakeBus
            retryInterval: 20
        }
    }

    Component {
        id: engineComponent
        FmEngine { }
    }

    SignalSpy { id: failedSpy; signalName: "failed" }

    TestCase {
        name: "FmRadio"
        when: windowShown

        property var radio: null

        function init() {
            root.calls = [];
            root.subscription = null;
            root.subscribes = 0;
            root.cancels = 0;
            root.answerNow = true;
            root.answers = {};
            root.failAtOnce = false;
            radio = createTemporaryObject(radioComponent, root);
            verify(radio);
            failedSpy.clear();
            failedSpy.target = radio;
        }

        // --- js/FmRadio.js ------------------------------------------------

        function test_paths() {
            compare(Fm.pathFor(95000), "fm:95000");
            compare(Fm.khzOf("fm:95000"), 95000);
            compare(Fm.khzOf("fm:abc"), 0);
            compare(Fm.khzOf("/media/internal/a.mp3"), 0);
            verify(Fm.isFm("fm:95000"));
            verify(!Fm.isFm("spotify:track:1"));
            verify(!Fm.isFm(""));
        }

        function test_valid_channels() {
            verify(Fm.valid(87500));
            verify(Fm.valid(108000));
            verify(Fm.valid(95000));
            verify(!Fm.valid(87400));
            verify(!Fm.valid(108100));
            verify(!Fm.valid(95050));
        }

        function test_titles() {
            compare(Fm.mhz(95000), "95.0");
            compare(Fm.mhz(107900), "107.9");
            compare(Fm.mhz(87500), "87.5");
            compare(Fm.title(100100), "100.1 FM");
        }

        function test_step_wraps_round_the_band() {
            compare(Fm.step(95000, 1), 95100);
            compare(Fm.step(95000, -1), 94900);
            compare(Fm.step(108000, 1), 87500);
            compare(Fm.step(87500, -1), 108000);
        }

        function test_track() {
            var t = Fm.track(95000);
            compare(t.path, "fm:95000");
            compare(t.title, "95.0 FM");
            compare(t.provider, "fm");
            verify(t.remote);
            compare(t.duration, 0);
        }

        function test_status_filled_in() {
            var s = Fm.status(status({ powered: true, rssi: -70, audio: true,
                                       stations: [95000, 95050, 200000, 100100] }));
            verify(s.ok);
            verify(s.available);
            verify(s.powered);
            verify(s.sounding);
            compare(s.rssi, -70);
            compare(s.stations, [95000, 100100]);
            compare(s.busy, "");
        }

        function test_status_of_nothing_is_no_radio() {
            var s = Fm.status("");
            verify(!s.available);
            verify(!s.powered);
            compare(s.rssi, null);
            compare(s.band.min, 87500);
            s = Fm.status("{not json");
            verify(!s.available);
            s = Fm.status({ returnValue: false, errorText: "no tuner" });
            verify(!s.ok);
            verify(!s.available);
            compare(s.errorText, "no tuner");
        }

        function test_status_busy() {
            compare(Fm.status(status({ busy: "seeking" })).busy, "seeking");
            compare(Fm.status(status({ busy: "scanning" })).busy, "scanning");
            compare(Fm.status(status({ busy: "naming" })).busy, "naming");
            compare(Fm.status(status({ busy: "bogus" })).busy, "");
        }

        function test_track_with_name_and_text() {
            var t = Fm.track(95000, "100% NL", "Onair: Guus Meeuwis");
            compare(t.title, "100% NL");
            compare(t.artist, "Onair: Guus Meeuwis");
            compare(t.album, "95.0 FM");
            compare(t.path, "fm:95000");
            t = Fm.track(95000, "", "");
            compare(t.title, "95.0 FM");
            compare(t.artist, "FM Radio");
        }

        function test_status_rds() {
            var s = Fm.status(status({ powered: true, rds: { name: " 100% NL ", text: "Onair" } }));
            compare(s.rdsName, "100% NL");
            compare(s.rdsText, "Onair");
            // Off: nothing is on the air, whatever came along.
            s = Fm.status(status({ powered: false, rds: { name: "100% NL", text: "Onair" } }));
            compare(s.rdsName, "");
            compare(s.rdsText, "");
            s = Fm.status(status({ powered: true }));
            compare(s.rdsName, "");
            s = Fm.status(status({ powered: true, rds: { name: 42, text: null } }));
            compare(s.rdsName, "");
            compare(s.rdsText, "");
            s = Fm.status(status({ powered: true, rds: { name: new Array(100).join("x") } }));
            compare(s.rdsName.length, 64);
        }

        function test_status_names() {
            // Heard whether on or off: kept by frequency, cleaned up.
            var s = Fm.status(status({ powered: false,
                                       names: { "95000": " 100% NL ", "99500": "NOORDZEE", "120000": "Off band",
                                                "95050": "Off grid", "x": "Not one", "101200": "", "104000": 7 } }));
            compare(s.names, { "95000": "100% NL", "99500": "NOORDZEE" });
            compare(Fm.status(status({})).names, {});
            compare(Fm.status(status({ names: ["95000"] })).names, {});
            compare(Fm.status(status({ names: { "95000": new Array(100).join("x") } })).names["95000"].length, 64);
            // A refusal is no list of names.
            compare(Fm.status({ returnValue: false, names: { "95000": "100% NL" } }).names, {});
        }

        function test_names() {
            var own = { "95000": "Mine" };
            var learned = { "95000": "100% NL", "100100": "RADIO 2" };
            compare(Fm.nameOf(95000, own, learned), "Mine");
            compare(Fm.nameOf(100100, own, learned), "RADIO 2");
            compare(Fm.nameOf(91000, own, learned), "");
            compare(Fm.nameOf(95000, null, null), "");
            compare(Fm.nameOf(95000, { "95000": "" }, learned), "100% NL");
            var m = Fm.withName(learned, 91000, " Sky ");
            compare(m["91000"], "Sky");
            compare(learned["91000"], undefined, "a new map");
            compare(Fm.withName(m, 91000, "Sky"), null);
            m = Fm.withName(m, 91000, "");
            compare(m["91000"], undefined);
            compare(Fm.withName(m, 91000, ""), null);
            compare(Fm.namesFrom("{\"95000\":\"x\"}")["95000"], "x");
            compare(Fm.namesFrom("[1]"), {});
            compare(Fm.namesFrom("nope"), {});
            compare(Fm.namesFrom("null"), {});
        }

        function test_reads_rds() {
            root.subscription.reply(status({ powered: true, rds: { name: "100% NL", text: "Onair" } }));
            compare(radio.rdsName, "100% NL");
            compare(radio.rdsText, "Onair");
            root.subscription.reply(status({ powered: true }));
            compare(radio.rdsName, "");
        }

        function test_bars() {
            compare(Fm.bars(null), 0);
            compare(Fm.bars(undefined), 0);
            compare(Fm.bars(-67), 4);
            compare(Fm.bars(-72), 4);
            compare(Fm.bars(-73), 3);
            compare(Fm.bars(-78), 3);
            compare(Fm.bars(-84), 2);
            compare(Fm.bars(-88), 1);
            compare(Fm.bars(-92), 0);
        }

        function test_station_list() {
            compare(Fm.stationList([100100, 95000, 100100, "x", 91000]), [91000, 95000, 100100]);
            compare(Fm.stationList(null), []);
        }

        // --- FmRadio.qml --------------------------------------------------

        function test_subscribes_on_start() {
            verify(root.subscription);
            compare(root.subscription.method, "getStatus");
            compare(root.subscription.payload.subscribe, true);
            verify(!radio.available);
        }

        function test_reads_the_status() {
            root.subscription.reply(status({ powered: true, frequency: 100100, rssi: -80,
                                             stations: [95000, 100100] }));
            verify(radio.available);
            verify(radio.powered);
            compare(radio.frequency, 100100);
            compare(radio.rssi, -80);
            compare(radio.stations, [95000, 100100]);
        }

        function test_a_service_that_goes_is_no_radio_and_is_asked_again() {
            root.subscription.reply(status({}));
            verify(radio.available);
            root.subscription.fail("gone");
            verify(!radio.available);
            compare(root.cancels, 1);
            tryCompare(root, "subscribes", 2);
        }

        function test_a_refusal_is_no_radio() {
            root.subscription.reply(status({}));
            root.subscription.reply({ returnValue: false, errorText: "no tuner" });
            verify(!radio.available);
            tryCompare(root, "subscribes", 2);
        }

        // The app's handle not registered yet: the subscribe that failed at
        // once is not kept, so it is tried again, and at once when the bus
        // says it is ready.
        function test_a_bus_not_ready_is_asked_again() {
            var r;
            root.failAtOnce = true;
            root.subscription = null;
            root.subscribes = 0;
            r = createTemporaryObject(radioComponent, root, { retryInterval: 60000 });
            compare(root.subscribes, 1);
            verify(!r.available);
            root.failAtOnce = false;
            fakeBus.initialized();
            compare(root.subscribes, 2);
            verify(root.subscription);
            root.subscription.reply(status({}));
            verify(r.available);
            // Ready again later: already subscribed, nothing more.
            fakeBus.initialized();
            compare(root.subscribes, 2);
        }

        function test_a_bus_not_ready_is_retried() {
            var r;
            root.failAtOnce = true;
            root.subscribes = 0;
            r = createTemporaryObject(radioComponent, root);
            compare(root.subscribes, 1);
            root.failAtOnce = false;
            tryCompare(root, "subscribes", 2);
            root.subscription.reply(status({}));
            verify(r.available);
        }

        function test_power_on_at_a_station() {
            var got = null;
            root.answers = { powerOn: { returnValue: true, frequency: 95000 } };
            radio.powerOn(95000, function(ok, khz) { got = [ok, khz]; });
            compare(sent("powerOn").length, 1);
            compare(sent("powerOn")[0].payload.frequency, 95000);
            compare(got, [true, 95000]);
        }

        function test_power_on_where_it_was() {
            radio.powerOn(0, null);
            compare(sent("powerOn")[0].payload.frequency, undefined);
        }

        function test_refused_power_on_is_reported() {
            var got = null;
            root.answers = { powerOn: { returnValue: false, errorText: "no /dev/fm" } };
            radio.powerOn(95000, function(ok, khz) { got = [ok, khz]; });
            compare(got, [false, 0]);
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][0], "powerOn");
            compare(failedSpy.signalArguments[0][1], "no /dev/fm");
        }

        function test_no_answer_is_reported() {
            var got = null;
            root.answerNow = false;
            radio.tune(95000, function(ok) { got = ok; });
            root.calls[0].fail("timeout");
            compare(got, false);
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][1], "timeout");
        }

        function test_unreadable_reply() {
            var got = null;
            root.answerNow = false;
            radio.powerOff(function(ok) { got = ok; });
            root.calls[0].reply("not json");
            compare(got, false);
        }

        function test_seek_directions() {
            root.answers = { seek: { returnValue: true, frequency: 100100 } };
            var got = null;
            radio.seek(1, function(ok, khz) { got = khz; });
            radio.seek(-1, null);
            compare(sent("seek")[0].payload.direction, "up");
            compare(sent("seek")[1].payload.direction, "down");
            compare(got, 100100);
        }

        function test_scan_gives_a_clean_list() {
            root.answers = { scan: { returnValue: true, stations: [100100, 95000, 95000] } };
            var got = null;
            radio.scan(function(ok, list) { got = [ok, list]; });
            compare(got, [true, [95000, 100100]]);
        }

        function test_find_names() {
            root.answers = { findNames: { returnValue: true, names: {} } };
            var got = null;
            radio.findNames([95000, 99500], function(ok) { got = ok; });
            compare(got, true);
            compare(sent("findNames")[0].payload, { stations: [95000, 99500] });
            root.answers = { findNames: { returnValue: false, errorCode: 16, errorText: "the radio is on" } };
            radio.findNames([95000], function(ok) { got = ok; });
            compare(got, false);
            // Names as they come in the status.
            root.subscription.reply(status({ names: { "95000": "100% NL" } }));
            compare(radio.names, { "95000": "100% NL" });
        }

        function test_no_bus() {
            var r = createTemporaryObject(radioComponent, root, { bus: null });
            var got = null;
            r.powerOn(95000, function(ok) { got = ok; });
            compare(got, false);
        }
    }

    TestCase {
        name: "FmEngine"
        when: windowShown

        property var radio: null
        property var engine: null

        function init() {
            root.calls = [];
            root.subscription = null;
            root.subscribes = 0;
            root.answerNow = true;
            root.failAtOnce = false;
            root.answers = { powerOn: { returnValue: true, frequency: 95000 } };
            radio = createTemporaryObject(radioComponent, root);
            engine = createTemporaryObject(engineComponent, root, { radio: radio });
            verify(engine);
        }

        function test_nothing_loaded() {
            verify(!engine.loaded);
            compare(engine.playbackState, MediaPlayer.StoppedState);
            engine.play();
            compare(sent("powerOn").length, 0);
        }

        function test_play_turns_the_radio_on_at_the_station() {
            engine.load("fm:95000");
            verify(engine.loaded);
            compare(sent("powerOn").length, 0);
            engine.play();
            compare(sent("powerOn").length, 1);
            compare(sent("powerOn")[0].payload.frequency, 95000);
            verify(engine.isPlaying);
            compare(engine.playbackState, MediaPlayer.PlayingState);
            verify(!engine.seekable);
            compare(engine.duration, 0);
        }

        function test_pause_turns_it_off() {
            engine.load("fm:95000");
            engine.play();
            engine.pause();
            verify(!engine.isPlaying);
            compare(engine.playbackState, MediaPlayer.PausedState);
            compare(sent("powerOff").length, 1);
            // Paused already: no second powerOff.
            engine.pause();
            compare(sent("powerOff").length, 1);
        }

        function test_another_station_while_playing_tunes() {
            engine.load("fm:95000");
            engine.play();
            engine.load("fm:100100");
            compare(sent("powerOn").length, 2);
            compare(sent("powerOn")[1].payload.frequency, 100100);
            verify(engine.isPlaying);
        }

        function test_another_station_while_paused_waits() {
            engine.load("fm:95000");
            engine.load("fm:100100");
            compare(sent("powerOn").length, 0);
        }

        function test_unload_switches_off() {
            engine.load("fm:95000");
            engine.play();
            engine.unload();
            verify(!engine.loaded);
            compare(sent("powerOff").length, 1);
        }

        function test_a_refusal_fails() {
            root.answers = { powerOn: { returnValue: false, errorText: "busy" } };
            var reasons = [];
            engine.failed.connect(function(r) { reasons.push(r); });
            engine.load("fm:95000");
            engine.play();
            verify(!engine.isPlaying);
            compare(reasons.length, 1);
            verify(engine.errorString !== "");
        }

        function test_a_late_answer_to_an_old_play_is_dropped() {
            root.answerNow = false;
            engine.load("fm:95000");
            engine.play();
            engine.pause();
            root.calls[0].reply({ returnValue: true, frequency: 95000 });
            verify(!engine.isPlaying);
        }

        function test_switched_off_elsewhere() {
            engine.load("fm:95000");
            engine.play();
            root.subscription.reply(status({ powered: true }));
            verify(engine.isPlaying);
            root.subscription.reply(status({ powered: false }));
            verify(!engine.isPlaying);
            // Another station does not turn it back on by itself...
            engine.load("fm:100100");
            compare(sent("powerOn").length, 1);
            // ...play does.
            engine.play();
            compare(sent("powerOn").length, 2);
            compare(sent("powerOn")[1].payload.frequency, 100100);
        }

        function test_no_radio() {
            var e = createTemporaryObject(engineComponent, root, { radio: null });
            var reasons = [];
            e.failed.connect(function(r) { reasons.push(r); });
            e.load("fm:95000");
            e.play();
            compare(reasons.length, 1);
        }
    }
}
