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
import "../js/Streaming.js" as Streaming

/*
 * Home: where the user left off, to jump back in - the song or station the
 * queue was left at, what was played last, the favourite stations and
 * songs, the user's playlists. Each list shows its first few, with "See
 * all" for the rest.
 */
Item {
    id: view

    property var theme: appWindow.theme
    // How many of each list Home shows.
    readonly property int few: 5

    readonly property var current: appWindow.player.current
    readonly property bool playing: appWindow.player.playing

    readonly property var rows: {
        appWindow.stats.revision;
        appWindow.playlists.revision;
        appWindow.library.revision;
        var out = [];
        if (current && !playing) {
            out.push({ kind: "header", name: "JUMP BACK IN" });
            out.push({ kind: "resume", track: current });
        }
        section(out, "RECENTLY PLAYED", "recentlyPlayed", appWindow.smartTracks("recentlyPlayed"));
        section(out, "FAVORITE STATIONS", "favoriteStations", appWindow.smartTracks("favoriteStations"));
        section(out, "FAVORITES", "favorites", appWindow.smartTracks("favorites"));
        var lists = appWindow.playlists.playlists;
        if (lists.length > 0) {
            out.push({ kind: "header", name: "YOUR PLAYLISTS" });
            lists.slice(0, few).forEach(function(p) {
                var first = p.tracks.length ? p.tracks[0] : null;
                out.push({ kind: "playlist", id: p._id, name: p.name, count: p.tracks.length,
                           artPath: first ? (typeof first === "object" ? first.path : first) : "",
                           artUrl: first && typeof first === "object" ? (first.artUrl || "") : "" });
            });
            if (lists.length > few)
                out.push({ kind: "all", category: "playlists" });
        }
        return out;
    }

    function section(out, name, id, tracks) {
        if (tracks.length === 0)
            return;
        out.push({ kind: "header", name: name });
        tracks.slice(0, few).forEach(function(t, i) {
            out.push({ kind: "track", list: id, track: t, index: i });
        });
        if (tracks.length > few)
            out.push({ kind: "all", smart: id });
    }

    /* A station plays on its own; a song plays its list from it, without the
     * stations in it. */
    function playFrom(listId, index) {
        var tracks = appWindow.smartTracks(listId);
        var t = tracks[index];
        if (!t)
            return;
        if (t.provider === "radio") {
            appWindow.player.playTracks([t], 0, false);
            return;
        }
        var songs = tracks.filter(function(x) { return x.provider !== "radio"; });
        appWindow.player.playTracks(songs, songs.indexOf(t), false);
    }

    function detailOf(t) {
        if (t.provider === "radio")
            return t.artist || "Internet Radio";
        return [t.artist, t.remote ? appWindow.streaming.providerName(t.provider) : ""]
            .filter(function(x) { return x; }).join(" · ");
    }

    ListView {
        id: list
        objectName: "homeList"
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
            width: list.width
            theme: view.theme
            title: modelData.kind === "all" ? "See all"
                   : modelData.kind === "playlist" ? modelData.name
                   : track ? track.title : ""
            subtitle: modelData.kind === "playlist" ? Library.plural(modelData.count, "song", "songs")
                      : modelData.kind === "resume" ? "Carry on with " + (view.detailOf(track) || "it")
                      : track ? view.detailOf(track) : ""
            icon: modelData.kind === "all" ? "more"
                  : modelData.kind === "playlist" ? "playlist"
                  : modelData.kind === "resume" ? "play"
                  : track && track.provider === "radio" ? "stream" : "note"
            artPath: track && !track.remote ? track.path : modelData.kind === "playlist" ? modelData.artPath : ""
            artAlbum: track && !track.remote ? (track.album || "") : ""
            artUrl: track && track.remote ? (track.artUrl || "") : modelData.kind === "playlist" ? modelData.artUrl : ""
            showMenu: modelData.kind === "track"
            onClicked: {
                if (modelData.kind === "resume")
                    appWindow.player.play();
                else if (modelData.kind === "track")
                    view.playFrom(modelData.list, modelData.index);
                else if (modelData.kind === "playlist")
                    appWindow.openPlaylist(modelData.id);
                else if (modelData.smart)
                    appWindow.openSmartPlaylist(modelData.smart);
                else
                    appWindow.pageStack.get(0).category = modelData.category;
            }
            onMenuRequested: appWindow.songMenu(track, null)
        }
    }

    StatusPanel {
        anchors.fill: parent
        theme: view.theme
        visible: view.rows.length === 0
        icon: "note"
        title: "Nothing here yet"
        text: "What you play, favourite and keep in playlists shows here, to carry on where you left off."
    }
}
