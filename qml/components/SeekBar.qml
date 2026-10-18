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
import LuneOS.Components 1.0 as LC

/*
 * Where the track is: the style's Slider, with the time gone and the time
 * left beside it, as Videos has it. While the finger is down the slider
 * follows it and the track is only moved on release, so dragging does not
 * stutter through a dozen seeks.
 */
Item {
    id: bar

    property real position: 0
    property real duration: 0
    property color textColor: "#a6a6a6"
    readonly property bool dragging: slider.pressed

    signal seekRequested(real ms)

    implicitHeight: Math.max(slider.implicitHeight, Units.gu(4)) + Units.gu(2.5)

    readonly property bool hours: duration >= 3600000

    Slider {
        id: slider
        objectName: "seekSlider"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        from: 0
        to: Math.max(1, bar.duration)
        enabled: bar.duration > 0
        live: true
        onPressedChanged: {
            if (!pressed)
                bar.seekRequested(value);
        }
        Binding on value {
            when: !slider.pressed
            value: Math.min(bar.position, Math.max(1, bar.duration))
            restoreMode: Binding.RestoreNone
        }
    }

    Text {
        objectName: "seekElapsed"
        anchors.left: parent.left
        anchors.top: slider.bottom
        text: LC.FileLists.formatClock(slider.value, bar.hours)
        color: bar.textColor
        font.pixelSize: FontUtils.sizeToPixels("small")
    }
    Text {
        objectName: "seekRemaining"
        anchors.right: parent.right
        anchors.top: slider.bottom
        visible: bar.duration > 0
        text: "-" + LC.FileLists.formatClock(Math.max(0, bar.duration - slider.value), bar.hours)
        color: bar.textColor
        font.pixelSize: FontUtils.sizeToPixels("small")
    }
}
