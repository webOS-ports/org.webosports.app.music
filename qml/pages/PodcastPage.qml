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
import "../js/Podcasts.js" as Podcasts

/*
 * A podcast: its picture, name and description, Subscribe (or what it
 * downloads by itself), and its episodes, newest first, a page at a time.
 * One the user has not subscribed to (found in the directory, or a feed
 * address) shows the same, from the feed as it is now.
 */
Item {
    id: page

    // One of the user's podcasts, or else the feed of one found.
    property string podcastId: ""
    property string feedUrl: ""
    // What is known before the service answers (a search result).
    property var info: ({})
    readonly property var store: appWindow.podcasts
    readonly property var theme: appWindow.theme

    readonly property string currentId: podcastId !== "" ? podcastId : store.subscribedId(feedUrl)
    readonly property bool subscribed: currentId !== "" && store.podcast(currentId) !== null
    readonly property var podcast: {
        var p = currentId !== "" ? store.podcast(currentId) : null;
        return p || _preview || info || {};
    }
    property string title: podcast.title || ""

    property var episodes: []
    property int next: -1
    property bool loading: false
    property bool loadingMore: false
    property string error: ""
    property var _preview: null
    property bool showAll: false

    Component.onCompleted: load()
    // Subscribed from here: the episodes are the service's from now on.
    onSubscribedChanged: if (subscribed) load()
    // A download, a position or a refresh changed something: the page again.
    Connections {
        target: page.store
        function onRevisionChanged() { if (page.subscribed && !page.loading && !page.loadingMore) page._reloadSoon.restart(); }
    }
    property Timer _reloadSoon: Timer { interval: 300; onTriggered: page.reload() }

    function load() {
        loading = true;
        error = "";
        if (currentId !== "") {
            store.episodes(currentId, 0, function(list, err, nextAt) {
                page.loading = false;
                page.episodes = list;
                page.next = nextAt;
                page.error = err;
            });
        } else if (feedUrl !== "") {
            store.preview(feedUrl, function(data, err) {
                page.loading = false;
                page._preview = data ? data.podcast : null;
                page.episodes = data && data.episodes ? data.episodes : [];
                page.next = -1;
                page.error = err;
            });
        }
    }

    // The pages shown so far, again.
    function reload() {
        if (currentId === "")
            return;
        var shown = Math.max(episodes.length, 50);
        var all = [];
        var step = function(offset) {
            store.episodes(currentId, offset, function(list, err, nextAt) {
                all = all.concat(list);
                if (nextAt >= 0 && all.length < shown) {
                    step(nextAt);
                    return;
                }
                if (!err) {
                    page.episodes = all;
                    page.next = nextAt;
                }
            });
        };
        step(0);
    }

    function more() {
        if (next < 0 || loadingMore)
            return;
        loadingMore = true;
        store.episodes(currentId, next, function(list, err, nextAt) {
            page.loadingMore = false;
            var seen = {};
            page.episodes.forEach(function(e) { seen[e.id] = true; });
            page.episodes = page.episodes.concat(list.filter(function(e) { return !seen[e.id]; }));
            page.next = nextAt;
        });
    }

    function subscribe() {
        store.subscribe(page.podcast.url || feedUrl, function(p, err) {
            if (!p)
                appWindow.notify(err || "The podcast cannot be read.");
            else
                page.podcastId = p.id;
        });
    }

    ListView {
        id: list
        objectName: "episodeList"
        anchors.fill: parent
        clip: true
        model: page.episodes
        cacheBuffer: page.theme.rowHeight * 10

        header: Column {
            width: list.width
            spacing: Units.gu(1)
            topPadding: Units.gu(2)
            bottomPadding: Units.gu(1)

            Row {
                x: page.theme.margin
                width: parent.width - 2 * page.theme.margin
                spacing: Units.gu(2)
                Cover {
                    id: art
                    width: Math.min(Units.gu(14), list.width * 0.3)
                    height: width
                    artUrl: page.podcast.image || ""
                    placeholderIcon: "podcast"
                }
                Column {
                    width: parent.width - art.width - parent.spacing
                    spacing: Units.gu(0.5)
                    anchors.verticalCenter: art.verticalCenter
                    Text {
                        objectName: "podcastTitle"
                        width: parent.width
                        text: page.podcast.title || ""
                        color: page.theme.text
                        font.pixelSize: page.theme.fontLarge
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.podcast.author || ""
                        visible: text !== ""
                        color: page.theme.accentOnLight
                        font.pixelSize: page.theme.fontMedium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: page.subscribed ? Podcasts.podcastDetail(page.podcast)
                              + (page.podcast.autoDownload > 0 ? " · Downloads " + Podcasts.autoDownloadLabel(page.podcast.autoDownload).toLowerCase() : "")
                              : ""
                        visible: text !== ""
                        color: page.theme.secondaryText
                        font.pixelSize: page.theme.fontSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Row {
                x: page.theme.margin
                spacing: Units.gu(1.5)
                Button {
                    objectName: "subscribeButton"
                    visible: !page.subscribed
                    enabled: !page.loading && (page.podcast.url || page.feedUrl)
                    text: "Subscribe"
                    LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                    onClicked: page.subscribe()
                }
                Button {
                    objectName: "playLatestButton"
                    visible: page.episodes.length > 0
                    text: "Play Latest"
                    LuneOSButton.mainColor: LuneOSButton.primaryColor
                    onClicked: appWindow.playEpisode(page.episodes, 0)
                }
                Button {
                    objectName: "podcastMenuButton"
                    visible: page.subscribed
                    text: "More…"
                    LuneOSButton.mainColor: LuneOSButton.secondaryColor
                    onClicked: appWindow.podcastMenu(page.podcast)
                }
            }

            Text {
                objectName: "podcastDescription"
                x: page.theme.margin
                width: parent.width - 2 * page.theme.margin
                text: page.podcast.description || ""
                visible: text !== ""
                color: page.theme.secondaryText
                font.pixelSize: page.theme.fontSmall
                wrapMode: Text.WordWrap
                maximumLineCount: page.showAll ? 1000 : 3
                elide: Text.ElideRight
                MouseArea {
                    anchors.fill: parent
                    onClicked: page.showAll = !page.showAll
                }
            }

            Text {
                x: page.theme.margin
                text: "EPISODES"
                visible: page.episodes.length > 0
                color: page.theme.accentOnLight
                font.pixelSize: page.theme.fontTiny
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }

        delegate: EpisodeRow {
            required property var modelData
            required property int index
            theme: page.theme
            episode: modelData
            playing: appWindow.player.current !== null && appWindow.player.current.path === modelData.id
            onClicked: appWindow.playEpisode(page.episodes, index)
            onMenuRequested: {
                if (page.subscribed)
                    appWindow.episodeMenu(modelData);
                else
                    appWindow.openEpisode(modelData);
            }
        }

        footer: Column {
            width: list.width
            ListRow {
                objectName: "moreEpisodesRow"
                width: parent.width
                visible: page.next >= 0
                theme: page.theme
                title: page.loadingMore ? "Loading…" : "More episodes"
                icon: "down"
                onClicked: page.more()
            }
            Item { width: 1; height: Units.gu(2) }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: page.loading
        visible: running
    }

    StatusPanel {
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height / 2
        theme: page.theme
        visible: !page.loading && page.episodes.length === 0
        icon: "podcast"
        title: page.error !== "" ? "The podcast cannot be read" : "No episodes"
        text: page.error
    }
}
