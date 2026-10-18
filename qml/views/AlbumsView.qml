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

/* Every album, as a grid of covers. */
Item {
    id: view

    property var theme: appWindow.theme
    property var library: appWindow.library
    property string sortBy: appWindow.prefs.albumSort

    readonly property var albums: {
        library.revision;
        return Library.sortAlbums(library.lib.albums, sortBy);
    }
    // Sort and shuffle, for the "..." of a short window (LibraryPage).
    readonly property var viewActions: [{ label: "Shuffle All", action: function() { appWindow.shuffleAll(); } },
                                        { label: "Sort By", header: true }].concat(
        [["title", "Title"], ["artist", "Artist"], ["year", "Year"], ["added", "Recently Added"]].map(function(o) {
            return { label: o[1], checked: view.sortBy === o[0], action: function() { appWindow.prefs.albumSort = o[0]; } };
        }))
    readonly property string playingKey: appWindow.player.current ? (appWindow.player.current.albumKey || "") : ""

    ViewBar {
        id: bar
        width: parent.width
        theme: view.theme
        visible: !status.needed && !(appWindow.compact && !appWindow.wide)
        countText: Library.plural(view.albums.length, "album", "albums")
        sortText: ({ title: "Title", artist: "Artist", year: "Year", added: "Recently added" })[view.sortBy] || "Title"
        onSortClicked: appWindow.chooseSort("Sort albums by", [
            { key: "title", text: "Title" }, { key: "artist", text: "Artist" },
            { key: "year", text: "Year" }, { key: "added", text: "Recently added" }
        ], view.sortBy, function(key) { appWindow.prefs.albumSort = key; })
        onShuffleClicked: appWindow.shuffleAll()
    }

    GridView {
        id: grid
        objectName: "albumsGrid"
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Units.gu(0.75)
        anchors.rightMargin: Units.gu(0.75)
        clip: true
        visible: !status.needed
        readonly property int columns: Math.max(2, Math.floor(width / Units.gu(14)))
        cellWidth: width / columns
        cellHeight: cellWidth + Units.gu(5.5)
        model: view.albums
        cacheBuffer: cellHeight * 2
        delegate: AlbumTile {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            album: modelData
            theme: view.theme
            playing: modelData.key === view.playingKey
            onClicked: appWindow.openAlbum(modelData)
            onMenuRequested: appWindow.albumMenu(modelData)
        }
    }

    LC.FastScroller {
        anchors.right: parent.right
        anchors.top: grid.top
        anchors.bottom: grid.bottom
        view: grid
        textColor: view.theme.secondaryText
        accentColor: view.theme.accentOnLight
        sections: view.sortBy === "title" ? view.albums.map(function(a) { return Library.sectionOf(a.title, true); })
                : (view.sortBy === "artist" ? view.albums.map(function(a) { return Library.sectionOf(a.artist, true); }) : [])
    }

    LibraryStatus {
        id: status
        anchors.fill: parent
        theme: view.theme
        library: view.library
    }
}
