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

import LunaNext.Common 0.1

/*
 * What a list shows when it has nothing to list: the library loading, no
 * music on the device yet, or the user not having allowed the app to read
 * it - with the button that fixes it, where there is one.
 */
Item {
    id: panel

    property var theme
    property string title: ""
    property string text: ""
    property string icon: "note"
    property string buttonText: ""
    property bool busy: false

    signal buttonClicked()

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Units.gu(4), Units.gu(45))
        spacing: Units.gu(1.5)

        BusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            running: panel.busy
            visible: panel.busy
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !panel.busy
            width: Units.gu(8)
            height: width
            source: Qt.resolvedUrl("../images/dark/" + panel.icon + ".svg")
            sourceSize.width: 128
            sourceSize.height: 128
            opacity: 0.3
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: panel.title
            color: panel.theme.text
            font.pixelSize: panel.theme.fontLarge
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: panel.text
            color: panel.theme.secondaryText
            font.pixelSize: panel.theme.fontSmall
            wrapMode: Text.WordWrap
            visible: text !== ""
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: panel.buttonText !== ""
            text: panel.buttonText
            onClicked: panel.buttonClicked()
        }
    }
}
