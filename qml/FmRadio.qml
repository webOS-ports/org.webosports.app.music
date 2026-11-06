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

import "js/FmRadio.js" as Fm

/*
 * The FM radio service (org.webosports.service.fmradio): its status, kept
 * by a subscription, and what can be asked of it. Tuning, seeking and
 * scanning only work with the radio on; the service plays it through
 * PulseAudio itself, so nothing here touches sound.
 *
 * A service that is not there - no tuner, or not installed - is simply no
 * radio: available stays false and the app shows no FM. One that goes away
 * is subscribed to again.
 *
 * Needs "fmradio.operation".
 */
QtObject {
    id: radio

    // A LunaService, or anything with its call() and subscribe().
    property var bus

    // after the service went or refused, subscribe again this much later
    property int retryInterval: 5000

    readonly property bool available: _status.available
    readonly property bool powered: _status.powered
    readonly property int frequency: _status.frequency
    // "", "seeking" or "scanning"
    readonly property string busy: _status.busy
    readonly property var stations: _status.stations
    readonly property var rssi: _status.rssi
    // What the station on says of itself over RDS: its name ("100% NL") and
    // its RadioText; "" until it has said it, and while the radio is off.
    readonly property string rdsName: _status.rdsName
    readonly property string rdsText: _status.rdsText
    readonly property var names: _status.names
    readonly property var band: _status.band
    // The radio is on and PulseAudio plays it.
    readonly property bool sounding: _status.sounding
    readonly property string errorText: _status.errorText

    // The whole status as one object (js/FmRadio.js status()): for reading
    // several fields that belong together. The properties above change one
    // after the other, so a handler of one can still see another's old value.
    readonly property var snapshot: _status

    // A request the service refused, with its reason.
    signal failed(string what, string reason)

    property var _status: Fm.status({ returnValue: true })
    property var _subscription: null
    // Set while bus.subscribe() runs: a call that fails at once (the app's
    // handle not registered yet) answers with its error before it returns.
    property bool _subscribing: false
    property bool _goneAtOnce: false

    property Timer _retry: Timer {
        interval: radio.retryInterval
        onTriggered: radio.subscribe()
    }

    function subscribe() {
        if (!bus || _subscription || _subscribing)
            return;
        _subscribing = true;
        _goneAtOnce = false;
        var s = bus.subscribe(Fm.SERVICE + "getStatus", JSON.stringify({ subscribe: true }),
                              _onStatus, _onGone);
        _subscribing = false;
        // LuneOS.Service hands back its call object even for a call that
        // failed: keeping it would stop every retry.
        if (_goneAtOnce) {
            if (s && s.cancel)
                s.cancel();
            return;
        }
        _subscription = s;
    }

    function _onStatus(message) {
        var s = Fm.status(message.payload);
        if (!s.ok) {
            _onGone(s.errorText);
            return;
        }
        _status = s;
    }

    function _onGone(error) {
        if (_subscribing)
            _goneAtOnce = true;
        if (_subscription && _subscription.cancel)
            _subscription.cancel();
        _subscription = null;
        _status = Fm.status({ returnValue: true });
        _retry.restart();
    }

    /* done(ok, reply) once the service answers. */
    function _ask(method, args, done) {
        if (!bus) {
            if (done)
                done(false, { errorText: "no bus" });
            return;
        }
        bus.call(Fm.SERVICE + method, JSON.stringify(args || {}), function(message) {
            var reply = {};
            try {
                reply = JSON.parse(message.payload);
            } catch (e) {
                reply = { returnValue: false, errorText: "unreadable reply" };
            }
            var ok = reply.returnValue === true;
            if (!ok)
                radio.failed(method, reply.errorText || "");
            if (done)
                done(ok, reply);
        }, function(error) {
            var reason = typeof error === "string" ? error
                         : (error && error.payload ? error.payload : "no answer");
            radio.failed(method, reason);
            if (done)
                done(false, { errorText: reason });
        });
    }

    /* On, at khz (0: where it was last). done(ok, khz). */
    function powerOn(khz, done) {
        _ask("powerOn", khz > 0 ? { frequency: khz } : {}, function(ok, reply) {
            if (done)
                done(ok, ok ? reply.frequency : 0);
        });
    }

    function powerOff(done) {
        _ask("powerOff", {}, function(ok) {
            if (done)
                done(ok);
        });
    }

    function tune(khz, done) {
        _ask("tune", { frequency: khz }, function(ok, reply) {
            if (done)
                done(ok, ok ? reply.frequency : 0);
        });
    }

    /* The next station up (dir > 0) or down. done(ok, khz). */
    function seek(dir, done) {
        _ask("seek", { direction: dir < 0 ? "down" : "up" }, function(ok, reply) {
            if (done)
                done(ok, ok ? reply.frequency : 0);
        });
    }

    /* Every station in the band, about ten seconds. done(ok, stations). */
    function scan(done) {
        _ask("scan", {}, function(ok, reply) {
            if (done)
                done(ok, ok ? Fm.stationList(reply.stations) : []);
        });
    }

    /* The names of stations (kHz), looked for by the service with the
     * radio off and no sound: they come in the status as they are found.
     * done(ok). */
    function findNames(stations, done) {
        _ask("findNames", { stations: stations }, function(ok) {
            if (done)
                done(ok);
        });
    }

    // The app's LunaService registers with the hub after it is created:
    // until then a call fails at once. Ask again as soon as it has.
    property Connections _ready: Connections {
        target: radio.bus && radio.bus.initialized !== undefined ? radio.bus : null
        ignoreUnknownSignals: true
        function onInitialized() {
            if (!radio._subscription) {
                radio._retry.stop();
                radio.subscribe();
            }
        }
    }

    property bool _complete: false
    // Another bus later on; the first one is asked once it is all set up.
    onBusChanged: if (_complete) subscribe()
    Component.onCompleted: {
        _complete = true;
        subscribe();
    }
}
