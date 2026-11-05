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
import "../js/Podcasts.js" as Podcasts

/*
 * Podcasts, in a tab of their own: finding one, the episodes started and
 * the new ones, the user's podcasts, the downloads, and the settings
 * (refreshing, downloading, import and export).
 */
Item {
    id: view

    property var theme: appWindow.theme
    readonly property var store: appWindow.podcasts
    // How many of the started and the new episodes show before "See all".
    property int few: 5

    readonly property var rows: {
        store.revision;
        var out = [{ kind: "search" }];
        var started = store.inProgress;
        if (started.length > 0) {
            out.push({ kind: "header", name: "CONTINUE LISTENING" });
            started.slice(0, few).forEach(function(e, i) { out.push({ kind: "episode", episode: e, list: started, index: i }); });
            if (started.length > few)
                out.push({ kind: "all", name: "Continue Listening", live: "inprogress", count: started.length });
        }
        var fresh = store.newEpisodes;
        if (fresh.length > 0) {
            out.push({ kind: "header", name: "NEW EPISODES" });
            fresh.slice(0, few).forEach(function(e, i) { out.push({ kind: "episode", episode: e, list: fresh, index: i }); });
            if (fresh.length > few)
                out.push({ kind: "all", name: "New Episodes", live: "new", count: fresh.length });
        }
        if (store.podcasts.length > 0) {
            out.push({ kind: "header", name: "YOUR PODCASTS" });
            store.podcasts.forEach(function(p) { out.push({ kind: "podcast", podcast: p }); });
        }
        out.push({ kind: "header", name: "MORE" });
        if (store.downloads.length > 0)
            out.push({ kind: "downloads", count: store.downloads.length });
        if (store.podcasts.length > 0)
            out.push({ kind: "refresh" });
        out.push({ kind: "settings" });
        return out;
    }

    ListView {
        id: list
        objectName: "podcastsList"
        anchors.fill: parent
        clip: true
        model: view.rows
        delegate: Loader {
            required property var modelData
            width: list.width
            sourceComponent: modelData.kind === "header" ? headerRow
                             : modelData.kind === "episode" ? episodeRow : itemRow
            property var rowData: modelData
        }
        footer: Item {
            width: list.width
            height: empty.visible ? empty.implicitHeight + Units.gu(4) : Units.gu(2)
            Text {
                id: empty
                visible: view.store.available && view.store.podcasts.length === 0
                anchors.top: parent.top
                anchors.topMargin: Units.gu(2)
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * view.theme.margin
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "No podcasts yet. Find one, add one by its feed address, or import a list from another app in the settings."
                color: view.theme.secondaryText
                font.pixelSize: view.theme.fontSmall
            }
        }
    }

    BusyIndicator {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Units.gu(1)
        width: Units.gu(3)
        height: width
        running: view.store.refreshing
        visible: running
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
        id: episodeRow
        EpisodeRow {
            readonly property var rowData: parent ? parent.rowData : ({})
            width: list.width
            theme: view.theme
            episode: rowData.episode || ({})
            withPodcast: true
            playing: appWindow.player.current !== null && appWindow.player.current.path === episode.id
            onClicked: appWindow.playEpisode(rowData.list, rowData.index)
            onMenuRequested: appWindow.episodeMenu(episode)
        }
    }

    Component {
        id: itemRow
        ListRow {
            readonly property var modelData: parent ? parent.rowData : ({})
            readonly property var podcast: modelData.podcast || null
            width: list.width
            theme: view.theme
            title: {
                switch (modelData.kind) {
                case "search": return "Find podcasts";
                case "all": return "See all";
                case "downloads": return "Downloads";
                case "refresh": return view.store.refreshing ? "Looking for new episodes…" : "Look for new episodes";
                case "settings": return "Podcast settings";
                }
                return podcast ? podcast.title : "";
            }
            subtitle: {
                switch (modelData.kind) {
                case "search": return "Search the directory, or add a feed's address";
                case "all": return modelData.name + " · " + modelData.count;
                case "downloads": return Podcasts.downloadsDetail(view.store.downloads);
                case "refresh": return "";
                case "settings": return "Refreshing, downloads, import and export";
                }
                return podcast ? Podcasts.podcastDetail(podcast) : "";
            }
            icon: modelData.kind === "search" ? "search" : modelData.kind === "downloads" ? "download"
                  : modelData.kind === "settings" ? "more" : modelData.kind === "refresh" ? "repeat" : "podcast"
            artUrl: podcast ? (podcast.image || "") : ""
            showMenu: !!podcast
            onClicked: {
                switch (modelData.kind) {
                case "search": appWindow.openPodcastSearch(); return;
                case "all": appWindow.openEpisodeList(modelData.name, null, modelData.live); return;
                case "downloads": appWindow.openEpisodeList("Downloads", null, "downloads"); return;
                case "refresh": view.store.refreshFeeds(""); return;
                case "settings": appWindow.openPodcastSettings(); return;
                }
                if (podcast)
                    appWindow.openPodcast(podcast);
            }
            onMenuRequested: appWindow.podcastMenu(podcast)
        }
    }
}
