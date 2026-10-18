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

import "../components"
import "../js/Library.js" as Library

/* Every genre. */
Item {
    id: view

    property var theme: appWindow.theme
    property var library: appWindow.library

    readonly property var genres: {
        library.revision;
        return library.lib.genres;
    }

    ListView {
        id: list
        objectName: "genresList"
        anchors.fill: parent
        clip: true
        visible: !status.needed
        model: view.genres
        delegate: ListRow {
            required property var modelData
            theme: view.theme
            title: modelData.name
            subtitle: Library.plural(modelData.albums.length, "album", "albums") + " · "
                      + Library.plural(modelData.songs.length, "song", "songs")
            artPath: modelData.artPath
            artAlbum: modelData.artAlbum
            icon: "genre"
            showMenu: true
            onClicked: appWindow.openGenre(modelData)
            onMenuRequested: appWindow.collectionMenu(modelData.name, modelData.songs)
        }
    }

    LibraryStatus {
        id: status
        anchors.fill: parent
        theme: view.theme
        library: view.library
    }
}
