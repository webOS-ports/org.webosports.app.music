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
 * The categories down the left of a tablet-wide window, as the legacy
 * Music app had them, with the playing track at the bottom.
 */
Rectangle {
    id: rail

    property var theme
    property var categories: []
    property string current: ""
    property var playingTrack: null

    signal categoryClicked(string id)
    signal nowPlayingClicked()

    color: theme.surface

    Column {
        width: parent.width
        topPadding: Units.gu(1)

        Repeater {
            model: rail.categories
            delegate: Item {
                required property var modelData
                width: rail.width
                height: Units.gu(6)
                readonly property bool selected: modelData.id === rail.current

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Units.gu(0.75)
                    anchors.rightMargin: Units.gu(0.75)
                    radius: Units.gu(0.8)
                    color: parent.selected ? "#f7f7f7" : (mouse.pressed ? rail.theme.pressed : "transparent")
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Units.gu(0.75)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Units.gu(0.4)
                    height: parent.height * 0.5
                    radius: width / 2
                    color: rail.theme.accentOnLight
                    visible: parent.selected
                }
                Image {
                    id: icon
                    anchors.left: parent.left
                    anchors.leftMargin: Units.gu(2.2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Units.gu(2.6)
                    height: width
                    source: Qt.resolvedUrl("../images/dark/" + modelData.icon + ".svg")
                    sourceSize.width: 64
                    sourceSize.height: 64
                    opacity: parent.selected ? 1 : 0.7
                }
                Text {
                    anchors.left: icon.right
                    anchors.leftMargin: Units.gu(1.5)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    color: parent.selected ? rail.theme.text : rail.theme.secondaryText
                    font.pixelSize: rail.theme.fontMedium
                    font.weight: parent.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    onClicked: rail.categoryClicked(modelData.id)
                }
            }
        }
    }
}
