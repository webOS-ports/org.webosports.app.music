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

import "js/MediaSession.js" as Session

/*
 * The player as a media session of com.webos.service.mediacontroller, so
 * that a Bluetooth headset's buttons work with the app in the background or
 * the screen off - not only, as media keys, with its window in front - and
 * audiod can pause it for a call like any other player.
 *
 * The session is registered once and lives as long as its subscription:
 * when the app goes, the service ends it. It is activated whenever playing
 * starts, which makes it the one the headset's keys go to, and the service
 * is told the play status and what plays, which a headset shows and which
 * audiod asks before it pauses anything.
 *
 * Needs "mediacontroller.query".
 */
Item {
    id: session

    // A LunaService, or anything with its call() and subscribe().
    property var bus
    property string appId
    property var player

    readonly property string mediaId: Session.sessionId(appId, Date.now())
    property bool registered: false

    // after a refusal or the service going, try again this much later
    property int retryInterval: 5000

    property var _call: null
    property string _sentStatus: ""
    property string _sentMeta: ""

    function register() {
        if (!bus || !appId || _call)
            return;
        _call = bus.subscribe(Session.SERVICE + "registerMediaSession",
                                  JSON.stringify(Session.registerPayload(mediaId, appId)),
                                  _onReply, _onError);
    }

    function unregister() {
        if (_call && _call.cancel)
            _call.cancel();
        _call = null;
        registered = false;
        _sentStatus = "";
        _sentMeta = "";
    }

    function _onReply(message) {
        var reply = Session.parseReply(message.payload, mediaId);
        if (reply.failed !== undefined) {
            _onError(reply.failed);
        } else if (reply.keyEvent !== undefined) {
            _act(Session.actionForKey(reply.keyEvent));
        } else if (reply.registered !== undefined && !registered) {
            registered = true;
            _report(true);
        }
    }

    function _onError(error) {
        console.warn("Music: no media session: " + error);
        unregister();
        retry.restart();
    }

    function _act(action) {
        if (!player || action === "")
            return;
        if (action === "play")
            player.play();
        else if (action === "pause")
            player.pause();
        else if (action === "next")
            player.next();
        else if (action === "previous")
            player.previous();
    }

    function _send(method, payload) {
        bus.call(Session.SERVICE + method, JSON.stringify(payload), function() {},
                     function(error) { console.warn("Music: " + method + ": " + error); });
    }

    // Tells the service what changed since it was last told; with "all",
    // everything, as after registering.
    function _report(all) {
        if (!registered || !player)
            return;
        var status = Session.playStatus(player.playing, !!player.current);
        // playing again makes this the session the headset's keys go to
        if (player.playing && (all || _sentStatus !== status))
            _send("activateMediaSession", { "mediaId": mediaId });
        if (all || status !== _sentStatus) {
            _send("setMediaPlayStatus", { "mediaId": mediaId, "playStatus": status });
            _sentStatus = status;
        }
        var meta = Session.metaData(player.current, player.duration);
        var text = JSON.stringify(meta);
        if (all || text !== _sentMeta) {
            _send("setMediaMetaData", { "mediaId": mediaId, "mediaMetaData": meta });
            _sentMeta = text;
        }
    }

    Timer {
        id: retry
        interval: session.retryInterval
        onTriggered: session.register()
    }

    Connections {
        target: session.player
        ignoreUnknownSignals: true
        function onPlayingChanged() { session._report(false); }
        function onCurrentChanged() { session._report(false); }
        function onDurationChanged() { session._report(false); }
    }

    Component.onCompleted: register()
    Component.onDestruction: unregister()
}
