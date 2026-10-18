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

import "../js/Library.js" as Library

/*
 * A song in a list: its cover (or its track number, in an album), title,
 * a line under it, the length, and "…" for what else can be done with it.
 * The playing song is drawn in the accent colour.
 */
Item {
    id: row

    property var song: null
    property var theme
    // An album's list numbers its tracks instead of showing covers.
    property bool showNumber: false
    property bool showCover: !showNumber
    property string subtitle: song ? song.artist + " — " + song.album : ""
    property bool playing: false
    property bool favorite: false
    // The drag handle of an editable list (queue, playlist).
    property bool showHandle: false
    property bool showMore: true
    property alias handle: handleArea

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
        onPressAndHold: row.menuRequested()
    }

    Item {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: row.theme.margin
        anchors.verticalCenter: parent.verticalCenter
        width: row.showCover ? Units.gu(5) : (row.showNumber ? Units.gu(3.5) : 0)
        height: Units.gu(5)

        Cover {
            anchors.fill: parent
            visible: row.showCover
            path: row.showCover && row.song ? row.song.path : ""
            album: row.song ? row.song.album : ""
            artUrl: row.song && row.song.artUrl ? row.song.artUrl : ""
        }
        Text {
            anchors.centerIn: parent
            visible: row.showNumber && !row.playing
            text: row.song && row.song.track > 0 ? row.song.track : "–"
            color: row.theme.secondaryText
            font.pixelSize: row.theme.fontSmall
        }
        // The playing track: the play icon (the devices' font has no U+25B6).
        Image {
            anchors.centerIn: parent
            visible: row.showNumber && row.playing
            width: Units.gu(1.8)
            height: width
            source: Qt.resolvedUrl("../images/dark/play.svg")
            sourceSize.width: 48
            sourceSize.height: 48
        }
    }

    Column {
        anchors.left: lead.right
        anchors.leftMargin: row.theme.margin
        anchors.right: duration.left
        anchors.rightMargin: Units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(0.2)

        Text {
            width: parent.width
            text: row.song ? row.song.title : ""
            color: row.playing ? row.theme.accentOnLight : row.theme.text
            font.pixelSize: row.theme.fontMedium
            elide: Text.ElideRight
        }
        Row {
            width: parent.width
            spacing: Units.gu(0.5)
            visible: row.subtitle !== "" || row.favorite
            // The heart (the devices' font has no U+2665).
            Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: row.favorite
                width: Units.gu(1.6)
                height: width
                source: Qt.resolvedUrl("../images/dark/heart.svg")
                sourceSize.width: 48
                sourceSize.height: 48
            }
            Text {
                width: parent.width - (row.favorite ? Units.gu(2.1) : 0)
                text: row.subtitle
                color: row.theme.secondaryText
                font.pixelSize: row.theme.fontSmall
                elide: Text.ElideRight
            }
        }
    }

    Text {
        id: duration
        anchors.right: more.left
        anchors.verticalCenter: parent.verticalCenter
        text: row.song && row.song.duration > 0 ? Library.formatDuration(row.song.duration) : ""
        color: row.theme.faintText
        font.pixelSize: row.theme.fontSmall
    }

    IconButton {
        id: more
        anchors.right: handleBox.left
        anchors.verticalCenter: parent.verticalCenter
        image: "more"
        label: "More"
        iconSize: Units.gu(2.4)
        accent: row.theme.accentOnLight
        onLight: true
        visible: row.showMore
        onClicked: row.menuRequested()
    }

    Item {
        id: handleBox
        anchors.right: parent.right
        anchors.rightMargin: row.showHandle ? Units.gu(0.5) : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: row.showHandle ? Units.gu(5) : 0
        visible: row.showHandle

        Image {
            anchors.centerIn: parent
            width: Units.gu(2.6)
            height: width
            source: Qt.resolvedUrl("../images/drag.svg")
            sourceSize.width: 64
            sourceSize.height: 64
            opacity: 0.6
        }
        MouseArea {
            id: handleArea
            anchors.fill: parent
        }
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
