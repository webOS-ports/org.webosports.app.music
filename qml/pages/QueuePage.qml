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

import "../components"
import "../js/Library.js" as Library
import "../js/Streaming.js" as Streaming

/*
 * Up next: the queue in play order. Tap to play from there, drag the
 * handle to reorder, the cross to take a song out; save it all as a
 * playlist, or clear what is still to come.
 */
Item {
    id: page

    property string title: "Up Next"
    readonly property var theme: appWindow.theme
    readonly property var player: appWindow.player
    readonly property var items: player.queue.items

    Component.onCompleted: list.positionViewAtIndex(Math.max(0, player.currentPos), ListView.Beginning)

    Item {
        id: bar
        width: parent.width
        height: stacked ? Units.gu(6) + summary.height + page.theme.margin : Units.gu(6)

        // Short labels when the full ones would not leave room for the
        // summary (480 px with an hour-long queue); the summary on a line
        // of its own when not even those do (320 px - the buttons have a
        // minimum width).
        readonly property real room: width - summary.implicitWidth - 3 * page.theme.margin
        readonly property bool tight: fullLabels.width > room
        readonly property bool stacked: shortLabels.width > room

        Text {
            id: summary
            objectName: "queueSummary"
            anchors.left: parent.left
            anchors.leftMargin: page.theme.margin
            anchors.right: bar.stacked ? parent.right : buttons.left
            anchors.rightMargin: page.theme.margin
            y: bar.stacked ? page.theme.margin : (Units.gu(6) - height) / 2
            text: Library.summary(page.items)
            color: page.theme.secondaryText
            font.pixelSize: page.theme.fontSmall
            elide: Text.ElideRight
        }
        Row {
            id: fullLabels
            visible: false
            spacing: buttons.spacing
            Button { text: "Save as Playlist" }
            Button { text: "Clear Up Next" }
        }
        Row {
            id: shortLabels
            visible: false
            spacing: buttons.spacing
            Button { text: "Save" }
            Button { text: "Clear" }
        }
        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: page.theme.margin
            anchors.bottom: parent.bottom
            anchors.bottomMargin: (Units.gu(6) - height) / 2
            spacing: Units.gu(1)
            Button {
                objectName: "saveQueue"
                text: bar.tight ? "Save" : "Save as Playlist"
                LuneOSButton.mainColor: LuneOSButton.secondaryColor
                enabled: page.items.length > 0
                onClicked: appWindow.newPlaylist(page.items.map(Streaming.stored))
            }
            Button {
                objectName: "clearQueue"
                text: bar.tight ? "Clear" : "Clear Up Next"
                LuneOSButton.mainColor: LuneOSButton.secondaryColor
                enabled: page.player.currentPos < page.items.length - 1
                onClicked: page.player.clearUpcoming()
            }
        }
    }

    ListView {
        id: list
        objectName: "queueList"
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: page.items
        interactive: !drag.active
        cacheBuffer: page.theme.rowHeight * 10

        QtObject {
            id: drag
            property bool active: false
            property int from: -1
            property int to: -1
        }

        delegate: SongRow {
            id: row
            required property var modelData
            required property int index
            song: modelData
            theme: page.theme
            playing: index === page.player.currentPos
            showHandle: true
            showMore: false
            opacity: index < page.player.currentPos ? 0.5 : 1
            onClicked: page.player.jumpTo(index)
            onMenuRequested: appWindow.songMenu(modelData, { queueIndex: index })

            Connections {
                target: row.handle
                function onPressed(event) {
                    drag.active = true;
                    drag.from = row.index;
                    drag.to = row.index;
                }
                function onPositionChanged(event) {
                    if (!drag.active)
                        return;
                    var p = row.handle.mapToItem(list.contentItem, event.x, event.y);
                    var target = list.indexAt(10, p.y);
                    if (target >= 0)
                        drag.to = target;
                }
                function onReleased(event) {
                    if (drag.active && drag.to !== drag.from && drag.to >= 0)
                        page.player.moveItem(drag.from, drag.to);
                    drag.active = false;
                }
                function onCanceled() {
                    drag.active = false;
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                height: Units.gu(0.4)
                color: page.theme.accentOnLight
                visible: drag.active && drag.to === row.index && drag.from !== drag.to
                y: drag.to > drag.from ? parent.height - height : 0
            }

            IconButton {
                objectName: "removeFromQueue"
                anchors.right: parent.right
                anchors.rightMargin: Units.gu(5.5)
                anchors.verticalCenter: parent.verticalCenter
                image: "close"
                label: "Remove"
                iconSize: Units.gu(2.2)
                accent: page.theme.accentOnLight
                onLight: true
                onClicked: page.player.removeItem(row.index)
            }
        }
    }

    StatusPanel {
        anchors.fill: list
        theme: page.theme
        visible: page.items.length === 0
        icon: "queue"
        title: "Nothing queued"
        text: "Play an album, a playlist or a song, or use “Play next” and “Add to queue” on anything in the library."
    }
}
