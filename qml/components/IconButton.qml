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
import LuneOS.Forms 1.0 as Forms

/*
 * LuneOS.Forms' toolbar key with a picture from qml/images ("<image>.svg"):
 * white for the dark player, from images/dark for the light library.
 * "active" lights it (shuffle on, repeat on); "filled" puts it on an accent
 * disc, as the big play button is. "busy" shows a spinner in place of the
 * picture (the play button while a stream connects); it stays a button.
 */
Forms.IconToolButton {
    id: button

    property bool onLight: false
    property bool active: false
    property bool filled: false
    property color accent: "#3a87c8"
    property bool busy: false

    imageFolder: Qt.resolvedUrl(onLight ? "../images/dark/" : "../images/")
    appearance: onLight ? "plain" : "overlay"
    checked: active
    implicitWidth: Math.max(Units.gu(5.5), 54)
    implicitHeight: Math.max(Units.gu(5.5), 54)

    Accessible.name: busy ? "Loading" : label
    contentItem.visible: !busy

    // The style's grey ring on the light library; on the dark player and
    // the accent disc a white one (images/spinner.png: the same ring, its
    // shades as white's opacity), as the white pictures are.
    BusyIndicator {
        objectName: "iconButtonBusy"
        anchors.centerIn: parent
        running: button.busy && button.onLight
        visible: running
    }
    Image {
        objectName: "iconButtonBusyLight"
        anchors.centerIn: parent
        width: button.iconSize
        height: button.iconSize
        visible: button.busy && !button.onLight
        source: visible ? "../images/spinner.png" : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true

        RotationAnimator on rotation {
            running: button.busy && !button.onLight
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 800
        }
    }

    background: Rectangle {
        radius: button.filled ? width / 2 : Units.gu(0.6)
        color: button.filled ? (button.pressed ? Qt.darker(button.accent, 1.2) : button.accent)
             : button.onLight ? (button.pressed ? "#30000000" : "transparent")
             : (button.pressed ? "#55ffffff" : (button.checked ? "#33ffffff" : "transparent"))
    }
}
