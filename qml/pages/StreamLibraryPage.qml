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

/*
 * A streaming service with a library of its own (a Subsonic server): a way
 * to search it, its newest albums side by side, and its artists, each
 * opening as the artists and albums on the device do.
 */
Item {
    id: page

    property string providerId: ""
    readonly property string title: appWindow.streaming.providerName(providerId)
    readonly property var theme: appWindow.theme

    property var artists: []
    property var newest: []
    property int _pending: 0
    readonly property bool loading: _pending > 0
    property string error: ""

    function load() {
        error = "";
        _pending = 2;
        appWindow.streaming.browse(providerId, "albums", "newest", function(albums, err) {
            page.newest = albums;
            if (err)
                page.error = err;
            page._pending--;
        });
        appWindow.streaming.browse(providerId, "artists", "", function(list, err) {
            page.artists = list;
            if (err)
                page.error = err;
            page._pending--;
        });
    }

    Component.onCompleted: load()

    ListView {
        id: list
        objectName: "streamArtists"
        anchors.fill: parent
        clip: true
        model: page.artists
        cacheBuffer: page.theme.rowHeight * 10

        // The newest albums arrive after the page opened and grow the
        // header: until the list has been moved, it stays at its top.
        property bool moved: false
        onMovementStarted: moved = true
        onOriginYChanged: if (!moved) positionViewAtBeginning()

        header: Column {
            width: list.width

            ListRow {
                objectName: "streamLibrarySearch"
                width: parent.width
                theme: page.theme
                title: "Search " + page.title
                subtitle: "Songs on the server"
                icon: "search"
                onClicked: appWindow.openStreamingSearch(page.providerId, "")
            }

            Item {
                width: parent.width
                height: page.newest.length > 0 ? newestStrip.height + Units.gu(5) : 0
                visible: page.newest.length > 0
                Text {
                    x: page.theme.margin
                    y: Units.gu(1)
                    text: "NEWEST ALBUMS"
                    color: page.theme.accentOnLight
                    font.pixelSize: page.theme.fontTiny
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
                ListView {
                    id: newestStrip
                    objectName: "streamNewest"
                    y: Units.gu(4)
                    width: parent.width
                    height: Units.gu(21)
                    orientation: ListView.Horizontal
                    leftMargin: Units.gu(0.75)
                    rightMargin: Units.gu(0.75)
                    clip: true
                    model: page.newest
                    delegate: AlbumTile {
                        required property var modelData
                        width: Units.gu(15.5)
                        height: newestStrip.height
                        album: modelData
                        theme: page.theme
                        onClicked: appWindow.openAlbum(modelData)
                        onMenuRequested: appWindow.albumMenu(modelData)
                    }
                }
            }

            Item {
                width: parent.width
                height: page.artists.length > 0 ? Units.gu(4.5) : 0
                visible: page.artists.length > 0
                Text {
                    x: page.theme.margin
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Units.gu(0.8)
                    text: "ARTISTS"
                    color: page.theme.accentOnLight
                    font.pixelSize: page.theme.fontTiny
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
            }
        }

        delegate: ListRow {
            required property var modelData
            width: list.width
            theme: page.theme
            title: modelData.name
            subtitle: modelData.albumCount === 1 ? "1 album" : modelData.albumCount + " albums"
            artUrl: modelData.artUrl
            icon: "artist"
            round: true
            onClicked: appWindow.openServiceArtist(modelData)
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading && page.artists.length === 0
        visible: running
    }

    StatusPanel {
        anchors.fill: parent
        anchors.topMargin: page.theme.rowHeight
        theme: page.theme
        visible: !page.loading && page.artists.length === 0 && page.newest.length === 0
        icon: "stream"
        title: page.error !== "" ? "The library did not load" : "Nothing on the server yet"
        text: page.error
        buttonText: "Try Again"
        onButtonClicked: page.load()
    }
}
