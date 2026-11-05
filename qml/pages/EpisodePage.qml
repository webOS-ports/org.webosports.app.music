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
 * An episode: what its feed says of it, and playing (or going on with) it,
 * downloading it and marking it played.
 */
Item {
    id: page

    property var episode: ({})
    property string title: episode.podcastTitle || "Episode"
    readonly property var store: appWindow.podcasts
    readonly property var theme: appWindow.theme
    readonly property bool subscribed: !!episode.podcast && store.podcast(episode.podcast) !== null
    readonly property string downloadState: (episode.download || {}).state || "none"

    // The service's newer word on it (a download going on, a position).
    Connections {
        target: page.store
        function onRevisionChanged() { page._update(); }
    }
    function _update() {
        if (!subscribed)
            return;
        var lists = [store.inProgress, store.newEpisodes, store.downloads];
        for (var i = 0; i < lists.length; i++) {
            for (var j = 0; j < lists[i].length; j++) {
                if (lists[i][j].id === episode.id) {
                    episode = lists[i][j];
                    return;
                }
            }
        }
    }
    function _set(e) {
        if (e)
            episode = e;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: body.height + Units.gu(4)
        clip: true

        Column {
            id: body
            x: page.theme.margin
            y: Units.gu(2)
            width: flick.width - 2 * page.theme.margin
            spacing: Units.gu(1)

            Row {
                width: parent.width
                spacing: Units.gu(2)
                Cover {
                    id: art
                    width: Math.min(Units.gu(12), body.width * 0.3)
                    height: width
                    artUrl: page.episode.image || ""
                    placeholderIcon: "podcast"
                }
                Column {
                    width: parent.width - art.width - parent.spacing
                    anchors.verticalCenter: art.verticalCenter
                    spacing: Units.gu(0.5)
                    Text {
                        objectName: "episodeTitle"
                        width: parent.width
                        text: page.episode.title || ""
                        color: page.theme.text
                        font.pixelSize: page.theme.fontLarge
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: page.episode.podcastTitle || ""
                        visible: text !== ""
                        color: page.theme.accentOnLight
                        font.pixelSize: page.theme.fontMedium
                        elide: Text.ElideRight
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!page.episode.podcast
                            onClicked: appWindow.openPodcast({ id: page.episode.podcast })
                        }
                    }
                    Text {
                        objectName: "episodePageDetail"
                        width: parent.width
                        text: Podcasts.detailOf(page.episode, Date.now(), false)
                        color: page.theme.secondaryText
                        font.pixelSize: page.theme.fontSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: Units.gu(1.5)
                Button {
                    objectName: "episodePlayButton"
                    text: page.episode.video ? "Play in Videos"
                          : page.episode.position_ms > 0 && !page.episode.played ? "Resume" : "Play"
                    LuneOSButton.mainColor: LuneOSButton.primaryColor
                    onClicked: appWindow.playEpisode([page.episode], 0)
                }
                Button {
                    objectName: "episodeDownloadButton"
                    visible: page.subscribed
                    text: page.downloadState === "done" ? "Delete Download"
                          : page.downloadState === "queued" || page.downloadState === "downloading" ? "Stop Downloading"
                          : "Download"
                    LuneOSButton.mainColor: page.downloadState === "done" ? LuneOSButton.negativeColor : LuneOSButton.secondaryColor
                    onClicked: {
                        if (page.downloadState === "done")
                            page.store.deleteDownload(page.episode.id, page._set);
                        else if (page.downloadState === "queued" || page.downloadState === "downloading")
                            page.store.cancelDownload(page.episode.id, page._set);
                        else
                            page.store.download(page.episode.id, function(e, err) {
                                page._set(e);
                                if (err)
                                    appWindow.notify(err);
                            });
                    }
                }
                Button {
                    objectName: "episodePlayedButton"
                    visible: page.subscribed
                    text: page.episode.played ? "Mark as Not Played" : "Mark as Played"
                    LuneOSButton.mainColor: LuneOSButton.secondaryColor
                    onClicked: page.store.setState(page.episode.id, { played: !page.episode.played }, page._set)
                }
            }

            Text {
                width: parent.width
                visible: (page.episode.download || {}).state === "failed" && !!(page.episode.download || {}).error
                text: "The download failed: " + ((page.episode.download || {}).error || "")
                color: page.theme.secondaryText
                font.pixelSize: page.theme.fontSmall
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 1
                color: page.theme.divider
            }

            Text {
                objectName: "episodeDescription"
                width: parent.width
                text: page.episode.description || "This episode has no description."
                color: page.theme.text
                font.pixelSize: page.theme.fontSmall
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }
        }
    }
}
