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
import "../js/Streaming.js" as Streaming

/*
 * Internet Radio, in a tab of its own: searching for a station, the
 * favourite stations, the user's own station lists and Radio Browser's
 * (Most played, Jazz...). Shown while the radio account is in Accounts.
 */
Item {
    id: view

    property var theme: appWindow.theme

    readonly property var lists: {
        var s = appWindow.streaming.servicePlaylists.filter(function(x) { return x.provider === "radio"; })[0];
        return s ? s.playlists : [];
    }

    readonly property var rows: {
        appWindow.stats.revision;
        var out = [{ kind: "search" }];
        var favs = appWindow.smartTracks("favoriteStations");
        if (favs.length > 0) {
            out.push({ kind: "header", name: "FAVORITE STATIONS" });
            favs.forEach(function(t, i) { out.push({ kind: "station", track: t, index: i }); });
        }
        var own = lists.filter(function(p) { return p.id.indexOf("rb.") !== 0; });
        if (own.length > 0) {
            out.push({ kind: "header", name: "YOUR STATION LISTS" });
            own.forEach(function(p) { out.push({ kind: "list", playlist: p }); });
        }
        var rb = lists.filter(function(p) { return p.id.indexOf("rb.") === 0; });
        if (rb.length > 0) {
            out.push({ kind: "header", name: "RADIO BROWSER" });
            rb.forEach(function(p) { out.push({ kind: "list", playlist: p }); });
        }
        return out;
    }

    ListView {
        id: list
        objectName: "radioList"
        anchors.fill: parent
        clip: true
        model: view.rows
        delegate: Loader {
            required property var modelData
            width: list.width
            sourceComponent: modelData.kind === "header" ? headerRow : itemRow
            property var rowData: modelData
        }
        footer: Item { width: 1; height: Units.gu(2) }
    }

    Component {
        id: headerRow
        Item {
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
        id: itemRow
        ListRow {
            readonly property var modelData: parent ? parent.rowData : ({})
            readonly property var track: modelData.track || null
            readonly property var playlist: modelData.playlist || null
            width: list.width
            theme: view.theme
            title: modelData.kind === "search" ? "Search stations"
                   : track ? track.title : playlist ? playlist.name : ""
            subtitle: modelData.kind === "search" ? "Tens of thousands, from Radio Browser"
                      : track ? (track.artist || "")
                      // Under RADIO BROWSER, nothing more to say.
                      : playlist ? (playlist.tracks > 0 ? Streaming.countOf("radio", playlist.tracks) : "") : ""
            icon: modelData.kind === "search" ? "search" : track ? "stream" : "playlist"
            artUrl: track ? (track.artUrl || "") : playlist ? (playlist.thumbnail || "") : ""
            showMenu: modelData.kind === "station"
            onClicked: {
                if (modelData.kind === "search")
                    appWindow.openStreamingSearch("radio");
                else if (track)
                    appWindow.player.playTracks([track], 0, false);
                else if (playlist)
                    appWindow.openServicePlaylist("radio", playlist);
            }
            onMenuRequested: appWindow.songMenu(track, null)
        }
    }
}
