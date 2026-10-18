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

/* Every song. */
Item {
    id: view

    property var theme: appWindow.theme
    property var library: appWindow.library
    property string sortBy: appWindow.prefs.songSort

    readonly property var songs: {
        library.revision;
        return Library.sortSongs(library.lib.songs, sortBy);
    }
    // Sort and shuffle, for the "..." of a short window (LibraryPage).
    readonly property var viewActions: [{ label: "Shuffle All", action: function() { appWindow.player.playTracks(view.songs, -1, true); } },
                                        { label: "Sort By", header: true }].concat(
        [["title", "Title"], ["artist", "Artist"], ["album", "Album"], ["added", "Recently Added"], ["year", "Year"], ["duration", "Length"]].map(function(o) {
            return { label: o[1], checked: view.sortBy === o[0], action: function() { appWindow.prefs.songSort = o[0]; } };
        }))
    readonly property string playingPath: appWindow.player.current ? appWindow.player.current.path : ""

    ViewBar {
        id: bar
        width: parent.width
        theme: view.theme
        visible: !status.needed && !(appWindow.compact && !appWindow.wide)
        countText: Library.plural(view.songs.length, "song", "songs")
        sortText: ({ title: "Title", artist: "Artist", album: "Album", added: "Recently added", year: "Year", duration: "Length" })[view.sortBy] || "Title"
        onSortClicked: appWindow.chooseSort("Sort songs by", [
            { key: "title", text: "Title" }, { key: "artist", text: "Artist" }, { key: "album", text: "Album" },
            { key: "added", text: "Recently added" }, { key: "year", text: "Year" }, { key: "duration", text: "Length" }
        ], view.sortBy, function(key) { appWindow.prefs.songSort = key; })
        onShuffleClicked: appWindow.player.playTracks(view.songs, -1, true)
    }

    ListView {
        id: list
        objectName: "songsList"
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        visible: !status.needed
        model: view.songs
        cacheBuffer: view.theme.rowHeight * 10
        delegate: SongRow {
            required property var modelData
            required property int index
            song: modelData
            theme: view.theme
            playing: modelData.path === view.playingPath
            onClicked: appWindow.player.playTracks(view.songs, index, false)
            onMenuRequested: appWindow.songMenu(modelData, null)
        }
    }

    LC.FastScroller {
        anchors.right: parent.right
        anchors.top: list.top
        anchors.bottom: list.bottom
        view: list
        textColor: view.theme.secondaryText
        accentColor: view.theme.accentOnLight
        sections: view.sortBy === "title" ? view.songs.map(function(s) { return s.section; })
                : (view.sortBy === "artist" ? view.songs.map(function(s) { return Library.sectionOf(s.artist, true); })
                : (view.sortBy === "album" ? view.songs.map(function(s) { return Library.sectionOf(s.album, false); }) : []))
    }

    LibraryStatus {
        id: status
        anchors.fill: parent
        theme: view.theme
        library: view.library
    }
}
