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

import LuneOS.Components 1.0 as LC

import "../components"
import "../js/Library.js" as Library

/* Every artist with albums, and everyone who appears on someone else's. */
Item {
    id: view

    property var theme: appWindow.theme
    property var library: appWindow.library

    readonly property var viewActions: [{ label: "Shuffle All", action: function() { appWindow.shuffleAll(); } }]

    readonly property var artists: {
        library.revision;
        return library.lib.artists;
    }

    ViewBar {
        id: bar
        width: parent.width
        theme: view.theme
        visible: !status.needed && !(appWindow.compact && !appWindow.wide)
        countText: Library.plural(view.artists.length, "artist", "artists")
        onShuffleClicked: appWindow.shuffleAll()
    }

    ListView {
        id: list
        objectName: "artistsList"
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        visible: !status.needed
        model: view.artists
        delegate: ListRow {
            required property var modelData
            theme: view.theme
            title: modelData.name
            subtitle: (modelData.albums.length > 0 ? Library.plural(modelData.albums.length, "album", "albums") + " · " : "")
                      + Library.plural(modelData.songs.length, "song", "songs")
            artPath: modelData.artPath
            artAlbum: modelData.artAlbum
            icon: "artist"
            round: true
            showMenu: true
            onClicked: appWindow.openArtist(modelData)
            onMenuRequested: appWindow.collectionMenu(modelData.name, modelData.songs)
        }
    }

    LC.FastScroller {
        anchors.right: parent.right
        anchors.top: list.top
        anchors.bottom: list.bottom
        view: list
        textColor: view.theme.secondaryText
        accentColor: view.theme.accentOnLight
        sections: view.artists.map(function(a) { return a.section; })
    }

    LibraryStatus {
        id: status
        anchors.fill: parent
        theme: view.theme
        library: view.library
    }
}
