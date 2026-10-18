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

import LunaNext.Common 0.1

/*
 * The bar along the bottom of every page while something is queued: the
 * playing track, play/pause and next, and a thin line for how far it is.
 * Tap it, or swipe it up, for Now Playing; swipe sideways for the next or
 * previous track.
 */
Rectangle {
    id: mini

    property var player
    property var theme

    signal openRequested()

    color: theme.darkSurface

    readonly property var track: player ? player.current : null

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        height: Units.gu(0.3)
        width: mini.player && mini.player.duration > 0
               ? parent.width * Math.min(1, mini.player.position / mini.player.duration) : 0
        color: mini.theme.accent
    }

    MouseArea {
        anchors.fill: parent
        property real startX: 0
        property real startY: 0
        onPressed: function(event) { startX = event.x; startY = event.y; }
        onReleased: function(event) {
            var dx = event.x - startX, dy = event.y - startY;
            if (dy < -Units.gu(3) && Math.abs(dy) > Math.abs(dx))
                mini.openRequested();
            else if (Math.abs(dx) > Units.gu(6) && Math.abs(dx) > Math.abs(dy))
                dx < 0 ? mini.player.next() : mini.player.previous();
            else if (Math.abs(dx) < Units.gu(2) && Math.abs(dy) < Units.gu(2))
                mini.openRequested();
        }
    }

    Cover {

        onLight: false
        id: cover
        anchors.left: parent.left
        anchors.leftMargin: Units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        width: Units.gu(5.5)
        height: width
        path: mini.track ? mini.track.path : ""
        album: mini.track ? mini.track.album : ""
        artUrl: mini.track && mini.track.artUrl ? mini.track.artUrl : ""
    }

    Column {
        anchors.left: cover.right
        anchors.leftMargin: Units.gu(1.2)
        anchors.right: buttons.left
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: mini.track ? mini.track.title : ""
            color: mini.theme.darkText
            font.pixelSize: mini.theme.fontMedium
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: mini.track ? mini.track.artist : ""
            color: mini.theme.darkSecondaryText
            font.pixelSize: mini.theme.fontSmall
            elide: Text.ElideRight
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: Units.gu(0.5)
        anchors.verticalCenter: parent.verticalCenter

        IconButton {
            objectName: "miniPlayPause"
            image: mini.player && mini.player.playing ? "pause" : "play"
            label: mini.player && mini.player.playing ? "Pause" : "Play"
            accent: mini.theme.accent
            onClicked: mini.player.toggle()
        }
        IconButton {
            image: "next"
            label: "Next"
            accent: mini.theme.accent
            enabled: !!(mini.player && mini.player.hasNext)
            onClicked: mini.player.next()
        }
    }
}
