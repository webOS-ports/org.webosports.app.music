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

import "../js/Art.js" as Art

/*
 * An album cover, or a note on a tinted square while there is none (or it
 * is still being found). The cover is asked for at the size it is shown,
 * so a list row loads a small one and Now Playing a large one.
 */
Rectangle {
    id: cover

    property string path: ""
    property string album: ""
    // A streamed track's cover, on the web.
    property string artUrl: ""
    // The icon shown without a cover.
    // On the light library: a light square and a dark note.
    property bool onLight: true
    property string placeholderIcon: "note"
    readonly property url placeholder: Qt.resolvedUrl((onLight ? "../images/dark/" : "../images/") + placeholderIcon + ".svg")
    readonly property bool hasArt: image.status === Image.Ready && image.implicitWidth > 1

    color: onLight ? "#c4c4c4" : "#2b2b2b"
    radius: Math.max(2, width / 40)
    clip: true

    Image {
        anchors.centerIn: parent
        width: parent.width * 0.42
        height: width
        source: cover.placeholder
        sourceSize.width: 96
        sourceSize.height: 96
        opacity: cover.hasArt ? 0 : 0.35
        visible: opacity > 0
    }

    Image {
        id: image
        anchors.fill: parent
        source: Art.source(cover.path, cover.album, cover.artUrl)
        sourceSize.width: Math.ceil(cover.width)
        sourceSize.height: Math.ceil(cover.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: cover.hasArt ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
