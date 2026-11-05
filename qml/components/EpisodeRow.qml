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

import "../js/Podcasts.js" as Podcasts

/*
 * A podcast episode: its picture, its title, the date, how much is left and
 * whether it is downloaded, a dot while it is new, and a bar for how far
 * it was listened to.
 */
Item {
    id: row

    property var theme
    property var episode: ({})
    // The podcast's name in the line under it, in lists of several.
    property bool withPodcast: false
    property bool playing: false

    signal clicked()
    signal menuRequested()

    width: ListView.view ? ListView.view.width : implicitWidth
    height: row.theme.rowHeight + Units.gu(0.5)

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

    Cover {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: row.theme.margin
        anchors.verticalCenter: parent.verticalCenter
        width: Units.gu(5)
        height: width
        radius: Math.max(2, width / 40)
        artUrl: row.episode.image || ""
        color: "#c4c4c4"
        placeholderIcon: "podcast"
    }

    Rectangle {
        objectName: "newDot"
        visible: row.episode.new === true && !row.episode.played
        anchors.horizontalCenter: lead.right
        anchors.verticalCenter: lead.top
        width: Units.gu(1.2)
        height: width
        radius: width / 2
        color: row.theme.accentOnLight
        border.color: "white"
        border.width: Math.max(1, Units.gu(0.15))
    }

    Column {
        anchors.left: lead.right
        anchors.leftMargin: row.theme.margin
        anchors.right: menuButton.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(0.2)

        Text {
            width: parent.width
            text: row.episode.title || ""
            color: row.playing ? row.theme.accentOnLight : (row.episode.played ? row.theme.secondaryText : row.theme.text)
            font.pixelSize: row.theme.fontMedium
            font.weight: row.playing ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "episodeDetail"
            width: parent.width
            text: Podcasts.detailOf(row.episode, Date.now(), row.withPodcast)
            color: row.theme.secondaryText
            font.pixelSize: row.theme.fontSmall
            elide: Text.ElideRight
            visible: text !== ""
        }
        Rectangle {
            visible: Podcasts.fractionOf(row.episode) > 0
            width: parent.width
            height: Math.max(2, Units.gu(0.3))
            radius: height / 2
            color: row.theme.divider
            Rectangle {
                width: parent.width * Podcasts.fractionOf(row.episode)
                height: parent.height
                radius: height / 2
                color: row.theme.accentOnLight
            }
        }
    }

    IconButton {
        id: menuButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
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
