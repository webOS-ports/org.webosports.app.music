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

import "js/ArtistInfo.js" as ArtistInfo

/*
 * About the playing artist, in Now Playing's place of the cover: a photo
 * with their name, how many follow them, who they are, their story and the
 * facts (ArtistLookup), and the way to their songs in the library.
 */
Item {
    id: view

    property var theme
    property string artist: ""
    // ArtistInfo.compose()'s info, or null.
    property var info: null
    // "searching", "found", "none", "failed" or "off" (NowPlaying).
    property string status: "none"
    // The library has songs by them.
    property bool inLibrary: false

    signal libraryRequested()
    signal retryRequested()

    Flickable {
        id: flick
        objectName: "artistFlick"
        anchors.fill: parent
        visible: view.info !== null
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + Units.gu(2)
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: flick.width
            spacing: Units.gu(1.2)

            // The photo, their name on it; without one (or until it is
            // there), just the name.
            Item {
                id: header
                objectName: "artistHeader"
                // Not photo.visible: inside the frame hidden without it, the
                // photo would never be visible.
                readonly property bool hasPhoto: photo.status === Image.Ready
                width: parent.width
                height: hasPhoto ? Math.max(Math.min(width * 0.62, Units.gu(36)), nameBlock.implicitHeight + Units.gu(3))
                                 : nameBlock.implicitHeight + Units.gu(3)

                Rectangle {
                    anchors.fill: parent
                    visible: header.hasPhoto
                    radius: Units.gu(1)
                    color: view.theme.darkRaised
                    clip: true
                    Image {
                        id: photo
                        objectName: "artistPhoto"
                        anchors.fill: parent
                        source: view.info ? view.info.image : ""
                        sourceSize.width: Math.ceil(width)
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                        asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.45; color: "#00000000" }
                            GradientStop { position: 1.0; color: "#cc000000" }
                        }
                    }
                }
                Column {
                    id: nameBlock
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Units.gu(1.5)
                    spacing: Units.gu(0.2)
                    Text {
                        text: "ABOUT THE ARTIST"
                        color: view.theme.darkSecondaryText
                        font.pixelSize: view.theme.fontTiny
                        font.letterSpacing: 1
                    }
                    Text {
                        objectName: "artistName"
                        width: parent.width
                        text: view.info ? view.info.name : ""
                        color: view.theme.darkText
                        font.pixelSize: view.theme.fontLarge * 1.25
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "artistFans"
                        visible: text !== ""
                        text: view.info && view.info.fans > 0 ? ArtistInfo.compactCount(view.info.fans) + " fans on Deezer" : ""
                        color: view.theme.darkSecondaryText
                        font.pixelSize: view.theme.fontSmall
                    }
                }
            }

            Text {
                objectName: "artistDescription"
                x: Units.gu(1.5)
                width: parent.width - Units.gu(3)
                visible: text !== ""
                // Wikidata's descriptions start in lower case.
                text: view.info && view.info.description ? view.info.description.charAt(0).toUpperCase() + view.info.description.substring(1) : ""
                color: view.theme.accent
                font.pixelSize: view.theme.fontMedium
                wrapMode: Text.Wrap
            }

            Text {
                objectName: "artistBio"
                x: Units.gu(1.5)
                width: parent.width - Units.gu(3)
                visible: text !== ""
                text: view.info ? view.info.bio : ""
                color: view.theme.darkText
                font.pixelSize: view.theme.fontSmall
                lineHeight: 1.15
                wrapMode: Text.Wrap
            }

            Column {
                x: Units.gu(1.5)
                width: parent.width - Units.gu(3)
                spacing: Units.gu(0.6)
                visible: factsRepeater.count > 0
                Repeater {
                    id: factsRepeater
                    model: view.info ? view.info.facts : []
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        spacing: Units.gu(1)
                        Text {
                            id: factLabel
                            width: Units.gu(11)
                            text: modelData.label
                            color: view.theme.darkSecondaryText
                            font.pixelSize: view.theme.fontSmall
                        }
                        Text {
                            width: parent.width - factLabel.width - parent.spacing
                            text: modelData.value
                            color: view.theme.darkText
                            font.pixelSize: view.theme.fontSmall
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            Rectangle {
                objectName: "artistLibraryButton"
                x: Units.gu(1.5)
                visible: view.inLibrary
                width: libraryText.implicitWidth + Units.gu(3)
                height: Math.max(Units.gu(4.5), 44)
                radius: height / 2
                color: libraryArea.pressed ? view.theme.darkPressed : "transparent"
                border.width: 1
                border.color: view.theme.accent
                Text {
                    id: libraryText
                    anchors.centerIn: parent
                    text: "Songs in your library"
                    color: view.theme.darkText
                    font.pixelSize: view.theme.fontSmall
                }
                MouseArea {
                    id: libraryArea
                    anchors.fill: parent
                    onClicked: view.libraryRequested()
                }
            }

            Text {
                objectName: "artistCredit"
                x: Units.gu(1.5)
                width: parent.width - Units.gu(3)
                visible: text !== ""
                text: {
                    var s = view.info ? view.info.sources : [];
                    if (!s || s.length === 0)
                        return "";
                    return "From " + s.join(" and ") + (s.indexOf("Wikipedia") >= 0 ? " (text CC BY-SA)" : "");
                }
                color: view.theme.darkFaintText
                font.pixelSize: view.theme.fontTiny
                wrapMode: Text.Wrap
            }
        }
    }

    Text {
        objectName: "artistStatus"
        anchors.centerIn: parent
        width: parent.width - Units.gu(4)
        visible: view.info === null
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: view.artist === "" ? "No artist for this song."
            : view.status === "searching" ? "Looking up " + view.artist + "…"
            : view.status === "failed" ? "Could not reach Wikipedia or Deezer.\nTap to try again."
            : view.status === "off" ? "Looking up artists online is off in Preferences."
            : "Nothing found about " + view.artist + "."
        color: view.theme.darkSecondaryText
        font.pixelSize: view.theme.fontSmall
        MouseArea {
            anchors.fill: parent
            anchors.margins: -Units.gu(2)
            enabled: view.status === "failed" && view.info === null
            onClicked: view.retryRequested()
        }
    }
}
