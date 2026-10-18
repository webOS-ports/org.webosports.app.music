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

/*
 * The strip at the top of a library view: how many there are, how they are
 * sorted (tap to change), and Shuffle.
 */
Item {
    id: bar

    property var theme
    property string countText: ""
    property string sortText: ""
    property bool showShuffle: true

    signal sortClicked()
    signal shuffleClicked()

    height: visible ? Math.max(Units.gu(6), 54) : 0

    Text {
        anchors.left: parent.left
        anchors.leftMargin: bar.theme.margin
        anchors.right: buttons.left
        anchors.verticalCenter: parent.verticalCenter
        text: bar.countText
        color: bar.theme.secondaryText
        font.pixelSize: bar.theme.fontSmall
        elide: Text.ElideRight
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.rightMargin: bar.theme.margin
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(1)

        Button {
            objectName: "sortButton"
            visible: bar.sortText !== ""
            // "Sort: Title": no arrow glyph, which the devices' font lacks.
            text: "Sort: " + bar.sortText
            LuneOSButton.mainColor: LuneOSButton.secondaryColor
            onClicked: bar.sortClicked()
        }
        Button {
            objectName: "shuffleAllButton"
            visible: bar.showShuffle
            text: "Shuffle"
            LuneOSButton.mainColor: LuneOSButton.primaryColor
            onClicked: bar.shuffleClicked()
        }
    }
}
