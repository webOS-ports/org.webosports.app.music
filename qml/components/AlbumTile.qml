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
 * An album in the grid: its cover, title and artist. Touch and hold for
 * what else can be done with it.
 */
Item {
    id: tile

    property var album: null
    property var theme
    property bool playing: false

    signal clicked()
    signal menuRequested()

    Cover {
        id: cover
        anchors.top: parent.top
        anchors.topMargin: Units.gu(0.75)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - Units.gu(1.5)
        height: width
        path: tile.album ? tile.album.artPath : ""
        album: tile.album ? tile.album.title : ""
        border.width: tile.playing ? Units.gu(0.3) : 0
        border.color: tile.theme.accentOnLight
    }

    Text {
        id: title
        anchors.top: cover.bottom
        anchors.topMargin: Units.gu(0.6)
        anchors.left: cover.left
        anchors.right: cover.right
        text: tile.album ? tile.album.title : ""
        color: tile.playing ? tile.theme.accentOnLight : tile.theme.text
        font.pixelSize: tile.theme.fontSmall
        font.weight: Font.Medium
        elide: Text.ElideRight
    }
    Text {
        anchors.top: title.bottom
        anchors.left: cover.left
        anchors.right: cover.right
        text: tile.album ? tile.album.artist : ""
        color: tile.theme.secondaryText
        font.pixelSize: tile.theme.fontTiny
        elide: Text.ElideRight
    }

    Rectangle {
        anchors.fill: cover
        radius: cover.radius
        color: tile.theme.pressed
        visible: mouse.pressed
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: tile.clicked()
        onPressAndHold: tile.menuRequested()
    }
}
