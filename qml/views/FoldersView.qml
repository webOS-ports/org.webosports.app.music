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

import MusicApp 1.0

import "../components"
import "../js/Library.js" as Library

/*
 * The music as it lies in folders, starting from the internal storage and
 * any card or stick that is in. Going into a folder stays in this view,
 * and the back gesture comes out of it again (there is no Up key: every
 * LuneOS device has the gesture).
 */
Item {
    id: view

    property var theme: appWindow.theme
    // "" lists the roots.
    property string path: ""
    property var trail: []
    property int revision: 0

    readonly property var entries: {
        revision;
        if (path === "")
            return files.roots(appWindow.internalStorage, appWindow.mediaRoot).map(function(r) {
                return { name: r.name, path: r.path, isDir: true, isPlaylist: false, isRoot: true };
            });
        return files.list(path);
    }
    readonly property var audioEntries: entries.filter(function(e) { return !e.isDir && !e.isPlaylist; })

    FileBrowser {
        id: files
    }

    function enter(dir) {
        trail = trail.concat([path]);
        path = dir;
    }

    /* Out of a folder; false at the top. */
    function back() {
        if (trail.length === 0)
            return false;
        path = trail[trail.length - 1];
        trail = trail.slice(0, trail.length - 1);
        return true;
    }

    function playFolder(dir, shuffle) {
        var paths = files.audioFilesUnder(dir, 5000);
        if (paths.length === 0) {
            appWindow.notify("There is no music in this folder.");
            return;
        }
        appWindow.player.playTracks(appWindow.library.tracksFor(paths), shuffle ? -1 : 0, shuffle);
    }

    Item {
        id: crumb
        width: parent.width
        height: view.path !== "" ? Units.gu(5) : 0
        visible: view.path !== ""

        Text {
            anchors.left: parent.left
            anchors.leftMargin: view.theme.margin
            anchors.right: playAll.left
            anchors.verticalCenter: parent.verticalCenter
            text: Library.fileName(view.path)
            color: view.theme.text
            font.pixelSize: view.theme.fontMedium
            elide: Text.ElideMiddle
        }
        IconButton {
            id: playAll
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            image: "more"
            label: "Folder actions"
            iconSize: Units.gu(2.4)
            accent: view.theme.accentOnLight
            onLight: true
            onClicked: appWindow.folderMenu(view.path, view)
        }
    }

    ListView {
        id: list
        objectName: "foldersList"
        anchors.top: crumb.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: view.entries
        delegate: ListRow {
            required property var modelData
            required property int index
            theme: view.theme
            title: modelData.name
            subtitle: modelData.isRoot ? modelData.path : (modelData.isPlaylist ? "Playlist file" : "")
            icon: modelData.isDir ? "folder" : (modelData.isPlaylist ? "playlist" : "note")
            artPath: !modelData.isDir && !modelData.isPlaylist ? modelData.path : ""
            showMenu: !modelData.isRoot
            onClicked: {
                if (modelData.isDir) {
                    view.enter(modelData.path);
                } else if (modelData.isPlaylist) {
                    appWindow.openPlaylistFile(modelData.path);
                } else {
                    var paths = view.audioEntries.map(function(e) { return e.path; });
                    appWindow.player.playTracks(appWindow.library.tracksFor(paths), paths.indexOf(modelData.path), false);
                }
            }
            onMenuRequested: {
                if (modelData.isDir)
                    appWindow.folderMenu(modelData.path, view);
                else if (modelData.isPlaylist)
                    appWindow.playlistFileMenu(modelData.path);
                else
                    appWindow.songMenu(appWindow.library.trackFor(modelData.path), null);
            }
        }
    }

    StatusPanel {
        anchors.fill: list
        theme: view.theme
        visible: view.entries.length === 0
        icon: "folder"
        title: view.path === "" ? "No storage found" : "Nothing to play here"
        text: view.path === "" ? "" : "This folder has no music or playlists in it."
    }
}
