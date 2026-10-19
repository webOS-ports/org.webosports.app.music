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

import Eos.Window 0.1
import LunaNext.Common 0.1

import "components"

/*
 * The dashboard in the notification area while music plays and the card
 * is not in front: the cover, the track, and previous / play-pause / next.
 * A tap anywhere else brings the card back. The card shell takes any
 * floating window as a dashboard and reads its height from
 * LuneOS_dashheight when the window first shows, so those are set first.
 */
WebOSWindow {
    id: dashboard

    property var player
    property var theme

    signal openRequested()
    // Swiped away in the notification area: the music stops with it (a
    // Spotify track plays in librespot, outside the app, and would go on).
    signal dismissed()

    property bool _shown: false

    readonly property var track: player ? player.current : null

    windowType: "_WEBOS_WINDOW_TYPE_FLOATING"
    width: Settings.displayWidth
    height: Units.gu(7)
    color: "transparent"
    visible: false

    Component.onCompleted: {
        setWindowProperty("LuneOS_window", "dashboard");
        setWindowProperty("LuneOS_metrics", "units");
        setWindowProperty("LuneOS_dashheight", "7");
        // The note, in the notification area's row of icons; relative to
        // the app's folder.
        setWindowProperty("LuneOS_icon", "qml/images/dashboard-icon.png");
        visible = true;
        _shown = true;
    }

    // Swiped away, the shell closes the window (luna-next-cardshell's
    // closeWindow): Eos.Window says so with windowCloseRequested and lets the
    // window go without its visible turning false. Hidden is the other way.
    onWindowCloseRequested: _dismiss()
    onVisibleChanged: if (!visible) _dismiss()

    function _dismiss() {
        if (!_shown)
            return;
        _shown = false;
        dashboard.dismissed();
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dashboard.openRequested()
    }

    Cover {

        onLight: false
        id: cover
        anchors.left: parent.left
        anchors.leftMargin: Units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        width: Units.gu(5)
        height: width
        path: dashboard.track ? dashboard.track.path : ""
        album: dashboard.track ? dashboard.track.album : ""
        artUrl: dashboard.track && dashboard.track.artUrl ? dashboard.track.artUrl : ""
    }

    Column {
        anchors.left: cover.right
        anchors.leftMargin: Units.gu(1.2)
        anchors.right: buttons.left
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: dashboard.track ? dashboard.track.title : ""
            color: "white"
            font.pixelSize: FontUtils.sizeToPixels("medium")
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: dashboard.track ? dashboard.track.artist : ""
            color: "#aaaaaa"
            font.pixelSize: FontUtils.sizeToPixels("small")
            elide: Text.ElideRight
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Units.gu(0.5)
        anchors.verticalCenter: parent.verticalCenter

        IconButton {
            image: "previous"
            label: "Previous"
            iconSize: Units.gu(2.6)
            accent: dashboard.theme.accent
            onClicked: dashboard.player.previous()
        }
        IconButton {
            image: dashboard.player && dashboard.player.playing ? "pause" : "play"
            label: dashboard.player && dashboard.player.playing ? "Pause" : "Play"
            iconSize: Units.gu(2.6)
            accent: dashboard.theme.accent
            onClicked: dashboard.player.toggle()
        }
        IconButton {
            image: "next"
            label: "Next"
            iconSize: Units.gu(2.6)
            enabled: !!(dashboard.player && dashboard.player.hasNext)
            accent: dashboard.theme.accent
            onClicked: dashboard.player.next()
        }
    }
}
