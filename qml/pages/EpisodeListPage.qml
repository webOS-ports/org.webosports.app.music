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

/*
 * Episodes of several podcasts: the new ones, those started, or the
 * downloads (live: as the service has them now, a download's progress
 * going up).
 */
Item {
    id: page

    property string title: ""
    property var fixed: []
    // "downloads", "new" or "inprogress": the store's list of that name.
    property string live: ""
    readonly property var store: appWindow.podcasts
    readonly property var theme: appWindow.theme

    readonly property var episodes: {
        store.revision;
        switch (live) {
        case "downloads": return store.downloads;
        case "new": return store.newEpisodes;
        case "inprogress": return store.inProgress;
        }
        return fixed;
    }

    ListView {
        id: list
        objectName: "episodeListPageList"
        anchors.fill: parent
        clip: true
        model: page.episodes
        delegate: EpisodeRow {
            required property var modelData
            required property int index
            theme: page.theme
            episode: modelData
            withPodcast: true
            playing: appWindow.player.current !== null && appWindow.player.current.path === modelData.id
            onClicked: appWindow.playEpisode(page.episodes, index)
            onMenuRequested: appWindow.episodeMenu(modelData)
        }
        footer: Item { width: 1; height: Units.gu(2) }
    }

    StatusPanel {
        anchors.fill: parent
        theme: page.theme
        visible: page.episodes.length === 0
        icon: page.live === "downloads" ? "download" : "podcast"
        title: page.live === "downloads" ? "No downloads" : "No episodes"
        text: page.live === "downloads" ? "Episodes downloaded play without a connection. Download one from its menu, or let a podcast download its newest ones." : ""
    }
}
