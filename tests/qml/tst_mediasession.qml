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

import "../../qml"
import "../../qml/js/MediaSession.js" as Session

/*
 * The media session (js/MediaSession.js, MediaSession.qml) against a fake
 * com.webos.service.mediacontroller and a fake player: what it registers,
 * what it tells the service and when, what each key does, and that a
 * refusal or the service going is retried and a session ended with the app.
 */
Item {
    id: root
    width: 100
    height: 100

    // --- the fake bus ------------------------------------------------------

    property var calls: []       // { method, payload } of every call()
    property var subscription: null
    property int cancels: 0

    function method(uri) { return uri.replace(Session.SERVICE, ""); }

    QtObject {
        id: fakeBus
        function subscribe(uri, args, onReply, onError) {
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
            root.calls.push({ method: root.method(uri), payload: JSON.parse(args) });
            onReply({ payload: "{\"returnValue\":true}" });
        }
    }

    function sent(name) {
        return calls.filter(function(c) { return c.method === name; });
    }

    // --- the fake player ---------------------------------------------------

    QtObject {
        id: fakePlayer
        property bool playing: false
        property var current: null
        property real duration: 0
        property var did: []
        function play() { did.push("play"); playing = true; }
        function pause() { did.push("pause"); playing = false; }
        function next() { did.push("next"); }
        function previous() { did.push("previous"); }
    }

    readonly property var song: ({ title: "Billie Jean", artist: "Michael Jackson", album: "Thriller",
                                   genre: "Pop", track: 6, duration: 294000 })

    Component {
        id: sessionComponent
        MediaSession {
            bus: fakeBus
            appId: "org.webosports.app.music"
            player: fakePlayer
            retryInterval: 20
        }
    }

    TestCase {
        name: "MediaSession"
        when: windowShown

        property var session: null

        function init() {
            root.calls = [];
            root.subscription = null;
            root.cancels = 0;
            fakePlayer.playing = false;
            fakePlayer.current = null;
            fakePlayer.duration = 0;
            fakePlayer.did = [];
            session = createTemporaryObject(sessionComponent, root);
            verify(session);
        }

        function registered() {
            root.subscription.reply({ returnValue: true, subscribed: true });
            verify(session.registered);
        }

        // --- js/MediaSession.js -------------------------------------------

        function test_keys() {
            compare(Session.actionForKey("play"), "play");
            compare(Session.actionForKey("pause"), "pause");
            compare(Session.actionForKey("stop"), "pause");
            compare(Session.actionForKey("next"), "next");
            compare(Session.actionForKey("previous"), "previous");
            compare(Session.actionForKey("volumeUp"), "");
            compare(Session.actionForKey(""), "");
        }

        function test_playStatus() {
            compare(Session.playStatus(true, true), "PLAYSTATE_PLAYING");
            compare(Session.playStatus(false, true), "PLAYSTATE_PAUSED");
            compare(Session.playStatus(false, false), "PLAYSTATE_STOPPED");
        }

        function test_metaData() {
            compare(Session.metaData(root.song, 0), { title: "Billie Jean", artist: "Michael Jackson",
                    album: "Thriller", genre: "Pop", totalDuration: "294", trackNumber: 6 });
            // the engine's duration over the indexer's, which is often 0
            compare(Session.metaData({ title: "x", duration: 0 }, 61400), { title: "x", totalDuration: "61" });
            compare(Session.metaData(null, 0), {});
        }

        function test_replies() {
            compare(Session.parseReply("{\"returnValue\":true,\"subscribed\":true}", "m"), { registered: true });
            compare(Session.parseReply({ returnValue: true, subscribed: true, keyEvent: "pause", mediaId: "m" }, "m"),
                    { keyEvent: "pause" });
            compare(Session.parseReply({ returnValue: true, keyEvent: "pause", mediaId: "other" }, "m"), {});
            compare(Session.parseReply({ returnValue: false, errorText: "Denied" }, "m"), { failed: "Denied" });
            compare(Session.parseReply("not json", "m"), { failed: "not JSON" });
        }

        function test_sessionIdsDifferPerRun() {
            verify(Session.sessionId("a", 1) !== Session.sessionId("a", 2));
            verify(Session.sessionId("a", 1).indexOf("a-") === 0);
        }

        // --- MediaSession.qml ---------------------------------------------

        function test_registersOnce() {
            verify(root.subscription);
            compare(root.subscription.method, "registerMediaSession");
            compare(root.subscription.payload.appId, "org.webosports.app.music");
            compare(root.subscription.payload.mediaId, session.mediaId);
            compare(root.subscription.payload.subscribe, true);
            session.register();
            compare(root.cancels, 0);
        }

        function test_tellsTheServiceOnceRegistered() {
            fakePlayer.current = root.song;
            fakePlayer.playing = true;
            compare(root.calls.length, 0, "nothing is sent before the session exists");
            registered();
            compare(sent("activateMediaSession").length, 1);
            compare(sent("setMediaPlayStatus")[0].payload.playStatus, "PLAYSTATE_PLAYING");
            compare(sent("setMediaMetaData")[0].payload.mediaMetaData.title, "Billie Jean");
            compare(sent("setMediaMetaData")[0].payload.mediaId, session.mediaId);
        }

        function test_followsThePlayer() {
            registered();
            fakePlayer.current = root.song;
            fakePlayer.playing = true;
            var activations = sent("activateMediaSession").length;
            fakePlayer.playing = false;
            compare(sent("setMediaPlayStatus").slice(-1)[0].payload.playStatus, "PLAYSTATE_PAUSED");
            compare(sent("activateMediaSession").length, activations, "pausing activates nothing");
            fakePlayer.playing = true;
            compare(sent("activateMediaSession").length, activations + 1,
                    "playing again takes the headset's keys back from another player");
            var metas = sent("setMediaMetaData").length;
            fakePlayer.duration = 0;
            compare(sent("setMediaMetaData").length, metas, "the same metadata is not sent again");
            fakePlayer.current = { title: "Beat It", duration: 258000 };
            compare(sent("setMediaMetaData").slice(-1)[0].payload.mediaMetaData.title, "Beat It");
        }

        function test_keysDriveThePlayer() {
            registered();
            var keys = ["pause", "play", "next", "previous", "stop", "volumeUp", "play", "play"];
            for (var i = 0; i < keys.length; i++)
                root.subscription.reply({ returnValue: true, subscribed: true, keyEvent: keys[i],
                                          mediaId: session.mediaId });
            compare(fakePlayer.did, ["pause", "play", "next", "previous", "pause", "play", "play"]);
            verify(fakePlayer.playing, "\"play\" twice is play, not a toggle");
        }

        function test_refusalIsRetried() {
            root.subscription.reply({ returnValue: false, errorText: "Denied" });
            verify(!session.registered);
            compare(root.cancels, 1);
            tryVerify(function() { return root.subscription !== null; }, 1000, "registers again");
            registered();
        }

        function test_serviceGoingIsRetried() {
            registered();
            root.subscription.fail("Service disconnected");
            verify(!session.registered);
            tryVerify(function() { return root.subscription !== null; }, 1000);
        }

        function test_endsWithTheApp() {
            registered();
            session.destroy();
            tryCompare(root, "cancels", 1);
        }
    }
}
