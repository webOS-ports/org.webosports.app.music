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
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1

import "components"
import "js/Art.js" as Art
import "js/Library.js" as Library

/*
 * Exhibition: what the device shows on its dock or stand. The cover
 * filling the background, a large clock, the track and where it is, and
 * big buttons to work from across the room. With nothing queued, a button
 * to shuffle the whole library.
 */
Rectangle {
    id: view

    property var player
    property var theme
    property bool use24h: true

    signal shuffleAllRequested()

    readonly property var track: player ? player.current : null
    // Side by side on a square screen too (the Q25): stacked, the cover
    // would push the controls off the bottom.
    readonly property bool landscape: width >= height * 0.9

    color: "black"

    Image {
        anchors.fill: parent
        source: view.track ? Art.source(view.track.path, view.track.album, view.track.artUrl) : ""
        sourceSize.width: 32
        sourceSize.height: 32
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        opacity: 0.5
    }
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55
    }

    property date now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: view.visible
        triggeredOnStart: true
        onTriggered: view.now = new Date()
    }

    // Sized from the screen, not grid units: exhibition fills the screen
    // whatever the device, and a large grid unit (the Q25's) would push it
    // off the edge.
    readonly property real u: Math.min(width, height) / 40

    Text {
        id: clock
        objectName: "exhibitionClock"
        x: view.landscape ? view.width - width - view.u * 3 : (view.width - width) / 2
        y: view.u * 2
        text: Qt.formatTime(view.now, view.use24h ? "HH:mm" : "h:mm")
        color: "white"
        font.pixelSize: view.u * 5
        font.weight: Font.Light
    }
    Text {
        id: date
        anchors.top: clock.bottom
        x: view.landscape ? view.width - width - view.u * 3 : (view.width - width) / 2
        text: Qt.formatDate(view.now, "dddd d MMMM")
        color: "#cccccc"
        font.pixelSize: view.u * 1.5
    }

    Cover {
        id: cover
        objectName: "exhibitionCover"
        onLight: false
        readonly property real coverSize: view.landscape
                                          ? Math.min(view.height - view.u * 6, view.width * 0.45)
                                          : Math.min(view.width - view.u * 8, view.height * 0.38)
        width: coverSize
        height: coverSize
        x: view.landscape ? view.u * 3 : (view.width - width) / 2
        y: view.landscape ? (view.height - height) / 2 : date.y + date.height + view.u * 2
        radius: view.u * 0.6
        path: view.track ? view.track.path : ""
        album: view.track ? view.track.album : ""
        artUrl: view.track && view.track.artUrl ? view.track.artUrl : ""
        visible: view.track !== null
    }

    Column {
        id: info
        visible: view.track !== null
        x: view.landscape ? cover.x + cover.width + view.u * 3 : view.u * 3
        width: view.landscape ? view.width - x - view.u * 3 : view.width - view.u * 6
        // Beside the cover, its foot level with the cover's but never up
        // into the clock; under it when stacked.
        y: view.landscape ? Math.max(date.y + date.height + view.u, cover.y + cover.height - height)
                          : cover.y + cover.height + view.u * 1.5
        spacing: view.u * 0.6

        Text {
            width: parent.width
            text: view.track ? view.track.title : ""
            color: "white"
            font.pixelSize: view.u * 2.4
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: view.landscape ? Text.AlignLeft : Text.AlignHCenter
        }
        Text {
            width: parent.width
            text: view.track ? view.track.artist + " — " + view.track.album : ""
            color: "#dddddd"
            font.pixelSize: view.u * 1.6
            elide: Text.ElideRight
            horizontalAlignment: view.landscape ? Text.AlignLeft : Text.AlignHCenter
        }
        SeekBar {
            width: parent.width
            position: view.player ? view.player.position : 0
            duration: view.player ? view.player.duration : 0
            textColor: "#cccccc"
            onSeekRequested: function(ms) { view.player.seek(ms); }
        }
        Row {
            x: view.landscape ? 0 : (parent.width - width) / 2
            spacing: view.u * 2
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                width: view.u * 5
                height: width
                image: "previous"
                label: "Previous"
                iconSize: view.u * 2.8
                accent: view.theme.accent
                onClicked: view.player.previous()
            }
            IconButton {
                objectName: "exhibitionPlayPause"
                anchors.verticalCenter: parent.verticalCenter
                width: view.u * 7
                height: width
                image: view.player && view.player.playing ? "pause" : "play"
                label: view.player && view.player.playing ? "Pause" : "Play"
                iconSize: view.u * 3.2
                filled: true
                accent: view.theme.accent
                onClicked: view.player.toggle()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                width: view.u * 5
                height: width
                image: "next"
                label: "Next"
                iconSize: view.u * 2.8
                enabled: !!(view.player && view.player.hasNext)
                accent: view.theme.accent
                onClicked: view.player.next()
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: view.track === null
        spacing: Units.gu(2)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nothing playing"
            color: "white"
            font.pixelSize: FontUtils.sizeToPixels("large")
        }
        Button {
            objectName: "exhibitionShuffleAll"
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Shuffle All"
            LuneOSButton.mainColor: LuneOSButton.primaryColor
            onClicked: view.shuffleAllRequested()
        }
    }
}
