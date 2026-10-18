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
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1

/*
 * The top of an album, artist, genre or playlist page: the cover, the name,
 * a line or two about it, and Play and Shuffle. Side by side when there is
 * room, the cover above the text in a narrow window.
 */
Item {
    id: header

    property var theme
    property string title: ""
    property string subtitle: ""
    property string detail: ""
    property string artPath: ""
    property string artAlbum: ""
    property string icon: "album"
    property bool round: false
    property bool canPlay: true

    signal playClicked()
    signal shuffleClicked()

    // Side by side in a window wider than it is tall too (the Q25's
    // 720x545 card), where a cover on top would fill the page.
    readonly property bool narrow: width < Units.gu(55) && !(Window.height > 0 && Window.width > Window.height)
    readonly property real coverSize: narrow ? Math.min(width * 0.55, Units.gu(26))
                                             : Math.max(Units.gu(10), Math.min(Units.gu(22), width * 0.4,
                                                   Window.height > 0 ? Window.height * 0.45 : Units.gu(22),
                                                   // room left for Play and Shuffle beside it
                                                   width - 2 * theme.margin - Units.gu(2.5) - actions.width))

    implicitHeight: narrow ? coverSize + textCol.implicitHeight + Units.gu(5)
                           : Math.max(coverSize, textCol.implicitHeight) + Units.gu(4)

    Cover {
        id: cover
        x: header.narrow ? (header.width - width) / 2 : header.theme.margin
        y: Units.gu(2)
        width: header.coverSize
        height: width
        radius: header.round ? width / 2 : Math.max(3, width / 40)
        path: header.artPath
        album: header.artAlbum
        placeholderIcon: header.icon
    }

    Column {
        id: textCol
        x: header.narrow ? header.theme.margin : cover.x + cover.width + Units.gu(2.5)
        y: header.narrow ? cover.y + cover.height + Units.gu(1.5) : cover.y + Math.max(0, (cover.height - implicitHeight) / 2)
        width: header.narrow ? header.width - 2 * header.theme.margin : header.width - x - header.theme.margin
        spacing: Units.gu(0.5)

        Text {
            width: parent.width
            text: header.title
            color: header.theme.text
            font.pixelSize: header.theme.fontLarge
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            horizontalAlignment: header.narrow ? Text.AlignHCenter : Text.AlignLeft
        }
        Text {
            width: parent.width
            text: header.subtitle
            visible: text !== ""
            color: header.theme.accentOnLight
            font.pixelSize: header.theme.fontMedium
            elide: Text.ElideRight
            horizontalAlignment: header.narrow ? Text.AlignHCenter : Text.AlignLeft
        }
        Text {
            width: parent.width
            text: header.detail
            visible: text !== ""
            color: header.theme.secondaryText
            font.pixelSize: header.theme.fontSmall
            elide: Text.ElideRight
            horizontalAlignment: header.narrow ? Text.AlignHCenter : Text.AlignLeft
        }
        Item { width: 1; height: Units.gu(0.5) }
        // Placed with x: anchors do not work inside a Column.
        Row {
            id: actions
            x: header.narrow ? (parent.width - width) / 2 : 0
            spacing: Units.gu(1.5)
            visible: header.canPlay

            Button {
                objectName: "playButton"
                text: "Play"
                LuneOSButton.mainColor: LuneOSButton.primaryColor
                onClicked: header.playClicked()
            }
            Button {
                objectName: "shuffleButton"
                text: "Shuffle"
                LuneOSButton.mainColor: LuneOSButton.secondaryColor
                onClicked: header.shuffleClicked()
            }
        }
    }
}
