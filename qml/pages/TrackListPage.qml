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
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1

import "../components"
import "../js/Library.js" as Library

/*
 * A page of songs under a cover: an album (numbered, by disc), an artist
 * or a genre (with their albums above), a playlist (which can be
 * reordered and trimmed in edit mode).
 */
Item {
    id: page

    property string title: ""
    property string subtitle: ""
    property string detail: Library.summary(songs)
    property string artPath: songs.length ? songs[0].path : ""
    property string artAlbum: songs.length ? songs[0].album : ""
    property string icon: "album"
    property bool roundCover: false
    property var songs: []
    // An album: track numbers instead of covers, and "Disc 2" between discs.
    property bool albumMode: false
    // Albums shown above the songs (an artist, a genre).
    property var albums: []
    // The user playlist this is, for editing; "" for none.
    property string playlistId: ""
    // The songs are still on their way (a streaming service's playlist).
    property bool loading: false
    property bool editing: false
    // Shown in the header's "…": [{ text, action }].
    property var actions: []
    readonly property var theme: appWindow.theme
    readonly property string playingPath: appWindow.player.current ? appWindow.player.current.path : ""
    readonly property bool canEdit: playlistId !== ""

    signal moveRequested(int from, int to)
    signal removeRequested(int index)

    // Rows: songs, with disc headers in a multi-disc album.
    readonly property var rows: {
        var out = [];
        var discs = albumMode && songs.some(function(s) { return s.disc > 1; });
        var lastDisc = -1;
        for (var i = 0; i < songs.length; i++) {
            var s = songs[i];
            if (discs && (s.disc || 1) !== lastDisc) {
                lastDisc = s.disc || 1;
                out.push({ disc: lastDisc });
            }
            out.push({ song: s, index: i });
        }
        return out;
    }

    function play(index, shuffle) {
        appWindow.player.playTracks(songs, index, shuffle);
    }

    ListView {
        id: list
        objectName: "trackList"
        anchors.fill: parent
        clip: true
        model: page.rows
        cacheBuffer: page.theme.rowHeight * 10
        interactive: !dragState.active

        header: Column {
            width: list.width

            CollectionHeader {
                objectName: "collectionHeader"
                width: parent.width
                theme: page.theme
                title: page.title
                subtitle: page.subtitle
                detail: page.detail
                artPath: page.artPath
                artAlbum: page.artAlbum
                icon: page.icon
                round: page.roundCover
                canPlay: page.songs.length > 0
                onPlayClicked: page.play(0, false)
                onShuffleClicked: page.play(-1, true)
            }

            // Albums of an artist or a genre, side by side.
            Item {
                width: parent.width
                height: page.albums.length > 0 ? albumStrip.height + Units.gu(5) : 0
                visible: page.albums.length > 0
                Text {
                    x: page.theme.margin
                    y: Units.gu(1)
                    text: "ALBUMS"
                    color: page.theme.accentOnLight
                    font.pixelSize: page.theme.fontTiny
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                ListView {
                    id: albumStrip
                    y: Units.gu(4)
                    width: parent.width
                    height: Units.gu(21)
                    orientation: ListView.Horizontal
                    leftMargin: Units.gu(0.75)
                    rightMargin: Units.gu(0.75)
                    clip: true
                    model: page.albums
                    delegate: AlbumTile {
                        required property var modelData
                        width: Units.gu(15.5)
                        height: albumStrip.height
                        album: modelData
                        theme: page.theme
                        onClicked: appWindow.openAlbum(modelData)
                        onMenuRequested: appWindow.albumMenu(modelData)
                    }
                }
            }

            Item {
                width: parent.width
                height: (page.albums.length > 0 || page.canEdit) ? Units.gu(4.5) : Units.gu(1)
                Text {
                    x: page.theme.margin
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Units.gu(0.8)
                    visible: page.albums.length > 0
                    text: "SONGS"
                    color: page.theme.accentOnLight
                    font.pixelSize: page.theme.fontTiny
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                Button {
                    objectName: "editButton"
                    anchors.right: parent.right
                    anchors.rightMargin: page.theme.margin
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.canEdit && page.songs.length > 0
                    text: page.editing ? "Done" : "Edit"
                    // Green Done, as the guidelines have it.
                    LuneOSButton.mainColor: page.editing ? LuneOSButton.affirmativeColor : LuneOSButton.secondaryColor
                    onClicked: page.editing = !page.editing
                }
            }
        }

        delegate: Loader {
            id: rowLoader
            required property var modelData
            required property int index
            width: list.width
            sourceComponent: modelData.disc !== undefined ? discRow : songRow
            property var rowData: modelData
            property int rowIndex: index
        }

        footer: Item { width: 1; height: Units.gu(2) }

        // Drag to reorder: the row follows the finger; on release the song
        // moves to where it was dropped.
        QtObject {
            id: dragState
            property bool active: false
            property int from: -1
            property int to: -1
        }
    }

    Component {
        id: discRow
        Item {
            height: Units.gu(4.5)
            Text {
                x: page.theme.margin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Units.gu(0.8)
                text: "DISC " + (parent.parent ? parent.parent.rowData.disc : "")
                color: page.theme.accentOnLight
                font.pixelSize: page.theme.fontTiny
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }
    }

    Component {
        id: songRow
        SongRow {
            id: row
            readonly property var rowInfo: parent ? parent.rowData : ({})
            song: rowInfo.song || null
            theme: page.theme
            showNumber: page.albumMode
            subtitle: song ? (page.albumMode ? (song.artist !== Library.unknownArtist ? song.artist : "")
                                             : song.artist + " — " + song.album) : ""
            playing: song !== null && song.path === page.playingPath
            favorite: song !== null && appWindow.stats.revision >= 0 && appWindow.stats.isFavorite(song.path)
            showHandle: page.editing
            showMore: !page.editing
            z: dragState.active && dragState.from === rowInfo.index ? 10 : 0
            onClicked: {
                if (page.editing)
                    return;
                page.play(rowInfo.index, false);
            }
            onMenuRequested: {
                if (page.editing)
                    page.removeRequested(rowInfo.index);
                else
                    appWindow.songMenu(song, page.canEdit ? { playlistId: page.playlistId, index: rowInfo.index } : null);
            }

            Connections {
                target: row.handle
                function onPressed(event) {
                    dragState.active = true;
                    dragState.from = row.rowInfo.index;
                    dragState.to = row.rowInfo.index;
                }
                function onPositionChanged(event) {
                    if (!dragState.active)
                        return;
                    var p = row.handle.mapToItem(list.contentItem, event.x, event.y);
                    var target = list.indexAt(10, p.y);
                    if (target >= 0 && page.rows[target] && page.rows[target].song)
                        dragState.to = page.rows[target].index;
                }
                function onReleased(event) {
                    if (dragState.active && dragState.to !== dragState.from && dragState.to >= 0)
                        page.moveRequested(dragState.from, dragState.to);
                    dragState.active = false;
                    dragState.from = -1;
                    dragState.to = -1;
                }
                function onCanceled() {
                    dragState.active = false;
                }
            }

            // Where the dragged song will land.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                height: Units.gu(0.4)
                color: page.theme.accentOnLight
                visible: dragState.active && dragState.to === row.rowInfo.index && dragState.from !== dragState.to
                y: dragState.to > dragState.from ? parent.height - height : 0
            }

            // In edit mode the "…" removes the song.
            Rectangle {
                visible: page.editing
                anchors.right: parent.right
                anchors.rightMargin: Units.gu(5.5)
                anchors.verticalCenter: parent.verticalCenter
                width: Units.gu(5)
                height: width
                color: "transparent"
                Image {
                    anchors.centerIn: parent
                    width: Units.gu(2.4)
                    height: width
                    source: Qt.resolvedUrl("../images/dark/close.svg")
                    sourceSize.width: 48
                    sourceSize.height: 48
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.removeRequested(row.rowInfo.index)
                }
            }
        }
    }

    BusyIndicator {
        objectName: "trackListBusy"
        anchors.centerIn: parent
        running: page.loading
        visible: page.loading
    }
}
