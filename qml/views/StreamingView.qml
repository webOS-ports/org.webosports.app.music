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
 * The streaming services signed in in Accounts (and YouTube, which needs
 * no account), each opening a search of that service.
 */
Item {
    id: view

    property var theme: appWindow.theme
    property var streaming: appWindow.streaming

    ListView {
        id: list
        objectName: "streamingList"
        anchors.fill: parent
        clip: true
        model: view.streaming.providers
        delegate: ListRow {
            required property var modelData
            theme: view.theme
            title: modelData.name
            subtitle: "Search " + modelData.name
            icon: "stream"
            onClicked: appWindow.openStreamingService(modelData.id)
        }
    }

    StatusPanel {
        anchors.fill: parent
        theme: view.theme
        visible: view.streaming.providers.length === 0
        icon: "stream"
        title: view.streaming.status === "unavailable" ? "Streaming is not running" : "No streaming services"
        text: view.streaming.status === "unavailable"
              ? "The music streaming service is not installed or not started."
              : "Add Spotify, Tidal, Deezer, Qobuz, Apple Music, SoundCloud, Jamendo or the Internet Archive in Accounts to play them here."
        buttonText: "Try Again"
        onButtonClicked: view.streaming.refresh()
    }
}
