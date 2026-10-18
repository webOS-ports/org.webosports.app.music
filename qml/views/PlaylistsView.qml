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

/*
 * The automatic playlists (favourites, recently added, most played...)
 * and the user's own, with New Playlist at the top.
 */
Item {
    id: view

    property var theme: appWindow.theme
    property var playlists: appWindow.playlists

    readonly property var rows: {
        playlists.revision;
        appWindow.stats.revision;
        appWindow.library.revision;
        var out = [{ kind: "new" }, { kind: "header", name: "AUTOMATIC" }];
        Library.smartPlaylists.forEach(function(s) {
            out.push({ kind: "smart", id: s.id, name: s.name,
                       count: appWindow.smartTracks(s.id).length });
        });
        if (playlists.playlists.length > 0)
            out.push({ kind: "header", name: "YOUR PLAYLISTS" });
        playlists.playlists.forEach(function(p) {
            // The first track's cover: a file's, or a streamed track's.
            var first = p.tracks.length ? p.tracks[0] : null;
            out.push({ kind: "user", id: p._id, name: p.name, count: p.tracks.length,
                       artPath: first ? (typeof first === "object" ? first.path : first) : "",
                       artUrl: first && typeof first === "object" ? (first.artUrl || "") : "" });
        });
        return out;
    }

    ListView {
        id: list
        objectName: "playlistsList"
        anchors.fill: parent
        clip: true
        model: view.rows
        delegate: Loader {
            required property var modelData
            width: list.width
            sourceComponent: modelData.kind === "header" ? headerRow : playlistRow
            property var rowData: modelData
        }
    }

    Component {
        id: headerRow
        Item {
            // The Loader it is in carries the row.
            readonly property var rowData: parent ? parent.rowData : null
            height: Units.gu(4.5)
            Text {
                anchors.left: parent.left
                anchors.leftMargin: view.theme.margin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Units.gu(0.8)
                text: parent.rowData ? parent.rowData.name : ""
                color: view.theme.accentOnLight
                font.pixelSize: view.theme.fontTiny
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }
    }

    Component {
        id: playlistRow
        ListRow {
            readonly property var modelData: parent ? parent.rowData : ({})
            width: list.width
            theme: view.theme
            title: modelData.kind === "new" ? "New Playlist" : modelData.name
            subtitle: modelData.kind === "new" ? "" : Library.plural(modelData.count, "song", "songs")
            icon: modelData.kind === "new" ? "playlist-add"
                  : (modelData.id === "favorites" ? "heart" : "playlist")
            artPath: modelData.kind === "user" ? modelData.artPath : ""
            artAlbum: modelData.kind === "user" && modelData.artPath ? appWindow.library.trackFor(modelData.artPath).album : ""
            artUrl: modelData.kind === "user" ? (modelData.artUrl || "") : ""
            showMenu: modelData.kind === "user"
            onClicked: {
                if (modelData.kind === "new")
                    appWindow.newPlaylist([]);
                else if (modelData.kind === "smart")
                    appWindow.openSmartPlaylist(modelData.id);
                else
                    appWindow.openPlaylist(modelData.id);
            }
            onMenuRequested: appWindow.playlistMenu(modelData.id)
        }
    }
}
