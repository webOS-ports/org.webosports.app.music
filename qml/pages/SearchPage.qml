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

import "../components"
import "../js/Library.js" as Library

/*
 * Search the library as you type: artists, albums and songs whose names
 * hold every word typed.
 */
Item {
    id: page

    property string title: "Search"
    property alias text: field.text
    readonly property var theme: appWindow.theme

    readonly property var result: {
        appWindow.library.revision;
        return Library.search(appWindow.library.lib, field.text, 30);
    }
    // A few results from each signed-in streaming service: { id: tracks }.
    property var remote: ({})
    property int _serial: 0

    function searchStreaming() {
        var serial = ++_serial;
        remote = {};
        var text = field.text.trim();
        if (text.length < 2)
            return;
        appWindow.streaming.providers.forEach(function(p) {
            appWindow.streaming.search(p.id, text, 5, function(tracks) {
                if (serial !== page._serial || tracks.length === 0)
                    return;
                var next = Object.assign({}, page.remote);
                next[p.id] = tracks;
                page.remote = next;
            });
        });
    }

    // The services are asked once typing pauses, not at every key.
    Timer {
        id: streamDebounce
        interval: 700
        onTriggered: page.searchStreaming()
    }

    readonly property var rows: {
        var out = [];
        if (result.artists.length) {
            out.push({ header: "ARTISTS" });
            result.artists.forEach(function(a) { out.push({ artist: a }); });
        }
        if (result.albums.length) {
            out.push({ header: "ALBUMS" });
            result.albums.forEach(function(a) { out.push({ album: a }); });
        }
        if (result.songs.length) {
            out.push({ header: "SONGS" });
            result.songs.forEach(function(s, i) { out.push({ song: s, index: i }); });
        }
        appWindow.streaming.providers.forEach(function(p) {
            var tracks = page.remote[p.id];
            if (!tracks || tracks.length === 0)
                return;
            out.push({ header: p.name.toUpperCase() });
            tracks.forEach(function(t, i) { out.push({ song: t, index: i, remoteTracks: tracks }); });
            out.push({ more: p.id, label: "More from " + p.name });
        });
        return out;
    }

    Component.onCompleted: field.forceActiveFocus()

    // Done typing: a result picked, Enter, or the list scrolled. The keyboard
    // goes with the field's focus.
    function dismissKeyboard() {
        field.focus = false;
        Qt.inputMethod.hide();
    }

    TextField {
        id: field
        objectName: "searchField"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Units.gu(1)
        placeholderText: "Artists, albums, songs"
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: streamDebounce.restart()
        onAccepted: page.dismissKeyboard()
    }

    ListView {
        id: list
        objectName: "searchResults"
        anchors.top: field.bottom
        anchors.topMargin: Units.gu(1)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: page.rows
        onMovementStarted: page.dismissKeyboard()
        delegate: Loader {
            required property var modelData
            width: list.width
            property var rowData: modelData
            sourceComponent: modelData.header ? headerRow : (modelData.more ? moreRow
                             : (modelData.artist ? artistRow : (modelData.album ? albumRow : songRow)))
        }
    }

    StatusPanel {
        anchors.fill: list
        theme: page.theme
        visible: field.text.trim() !== "" && page.rows.length === 0 && !streamDebounce.running
        icon: "search"
        title: "Nothing found"
        text: "No artist, album or song matches “" + field.text.trim() + "”."
    }

    Component {
        id: headerRow
        Item {
            height: Units.gu(4.5)
            Text {
                x: page.theme.margin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Units.gu(0.8)
                text: parent.parent ? parent.parent.rowData.header : ""
                color: page.theme.accentOnLight
                font.pixelSize: page.theme.fontTiny
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }
    }
    Component {
        id: moreRow
        ListRow {
            readonly property var d: parent ? parent.rowData : ({})
            theme: page.theme
            title: d.label || ""
            icon: "stream"
            onClicked: { page.dismissKeyboard(); appWindow.openStreamingService(d.more, field.text); }
        }
    }
    Component {
        id: artistRow
        ListRow {
            readonly property var a: parent ? parent.rowData.artist : null
            theme: page.theme
            title: a ? a.name : ""
            subtitle: a ? Library.plural(a.songs.length, "song", "songs") : ""
            artPath: a ? a.artPath : ""
            artAlbum: a ? a.artAlbum : ""
            icon: "artist"
            round: true
            onClicked: { page.dismissKeyboard(); appWindow.openArtist(a); }
        }
    }
    Component {
        id: albumRow
        ListRow {
            readonly property var al: parent ? parent.rowData.album : null
            theme: page.theme
            title: al ? al.title : ""
            subtitle: al ? al.artist : ""
            artPath: al ? al.artPath : ""
            artAlbum: al ? al.title : ""
            icon: "album"
            showMenu: true
            onClicked: { page.dismissKeyboard(); appWindow.openAlbum(al); }
            onMenuRequested: { page.dismissKeyboard(); appWindow.albumMenu(al); }
        }
    }
    Component {
        id: songRow
        SongRow {
            readonly property var d: parent ? parent.rowData : ({})
            song: d.song || null
            theme: page.theme
            playing: song !== null && appWindow.player.current !== null && appWindow.player.current.path === song.path
            subtitle: song ? (song.remote ? song.artist : song.artist + " \u2014 " + song.album) : ""
            onClicked: {
                page.dismissKeyboard();
                appWindow.player.playTracks(d.remoteTracks || page.result.songs, d.index, false);
            }
            onMenuRequested: { page.dismissKeyboard(); appWindow.songMenu(song, null); }
        }
    }
}
