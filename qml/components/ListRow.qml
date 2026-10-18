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
 * A row that leads somewhere - an artist, a genre, a playlist, a folder:
 * a cover or an icon, a title and a line under it, and "…" when there is
 * more to do than open it.
 */
Item {
    id: row

    property var theme
    property string title: ""
    property string subtitle: ""
    // A cover from this track, or else the icon.
    property string artPath: ""
    property string artAlbum: ""
    property string artUrl: ""
    property string icon: ""
    property bool round: false
    property bool showMenu: false

    signal clicked()
    signal menuRequested()

    width: ListView.view ? ListView.view.width : implicitWidth
    height: theme.rowHeight

    Rectangle {
        anchors.fill: parent
        color: mouse.pressed ? row.theme.pressed : "transparent"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: row.clicked()
        onPressAndHold: if (row.showMenu) row.menuRequested()
    }

    Cover {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: row.theme.margin
        anchors.verticalCenter: parent.verticalCenter
        width: Units.gu(5)
        height: width
        radius: row.round ? width / 2 : Math.max(2, width / 40)
        path: row.artPath
        album: row.artAlbum
        artUrl: row.artUrl
        placeholderIcon: row.icon !== "" ? row.icon : "note"
    }

    Column {
        anchors.left: lead.right
        anchors.leftMargin: row.theme.margin
        anchors.right: menuButton.visible ? menuButton.left : parent.right
        anchors.rightMargin: row.theme.margin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(0.2)

        Text {
            width: parent.width
            text: row.title
            color: row.theme.text
            font.pixelSize: row.theme.fontMedium
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: row.subtitle
            color: row.theme.secondaryText
            font.pixelSize: row.theme.fontSmall
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    IconButton {
        id: menuButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showMenu
        image: "more"
        label: "More"
        iconSize: Units.gu(2.4)
        accent: row.theme.accentOnLight
        onLight: true
        onClicked: row.menuRequested()
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: lead.right
        anchors.leftMargin: row.theme.margin
        anchors.right: parent.right
        height: 1
        color: row.theme.divider
    }
}
