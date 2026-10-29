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

import "js/Lyrics.js" as Lyrics

/*
 * The playing track's lyrics: from its tags, or a .lrc / .txt beside it.
 * Timed lyrics follow the music - the line being sung lit and kept in the
 * middle, and a tap on a line goes there; plain lyrics just scroll.
 */
Item {
    id: view

    property var theme
    property string text: ""
    property real position: 0
    // Who to credit: "" for the song's own lyrics, else the name of where
    // they were looked up.
    property string source: ""
    // "searching", "found", "instrumental", "none" or "failed" (NowPlaying).
    property string status: "none"
    // Only the song's own lyrics are looked for (no lookup online, a file).
    property bool ownOnly: false

    signal seekRequested(real ms)
    signal retryRequested()

    readonly property var parsed: Lyrics.parse(text)
    readonly property int currentLine: parsed.synced ? Lyrics.lineAt(parsed.lines, position + 300) : -1
    // Scrolled by hand: following the music pauses for a few seconds.
    property bool _userScrolled: false

    onCurrentLineChanged: {
        if (!_userScrolled && currentLine >= 0)
            list.positionViewAtIndex(currentLine, ListView.Center);
    }

    ListView {
        id: list
        objectName: "lyricsList"
        anchors.fill: parent
        clip: true
        model: view.parsed.lines
        topMargin: height / 3
        bottomMargin: height / 3
        highlightMoveDuration: 300
        onMovementStarted: { view._userScrolled = true; resumeFollow.stop(); }
        onMovementEnded: resumeFollow.restart()

        delegate: Text {
            required property var modelData
            required property int index
            width: list.width
            leftPadding: Units.gu(2)
            rightPadding: Units.gu(2)
            topPadding: Units.gu(0.6)
            bottomPadding: Units.gu(0.6)
            text: modelData.text === "" ? " " : modelData.text
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: view.parsed.synced ? view.theme.fontLarge : view.theme.fontMedium
            font.weight: index === view.currentLine ? Font.DemiBold : Font.Normal
            color: !view.parsed.synced || index === view.currentLine ? view.theme.darkText : view.theme.darkFaintText
            Behavior on color { ColorAnimation { duration: 200 } }
            MouseArea {
                anchors.fill: parent
                enabled: view.parsed.synced
                onClicked: view.seekRequested(modelData.time)
            }
        }
    }

    Timer {
        id: resumeFollow
        interval: 4000
        onTriggered: {
            view._userScrolled = false;
            if (view.currentLine >= 0)
                list.positionViewAtIndex(view.currentLine, ListView.Center);
        }
    }

    Text {
        objectName: "lyricsStatus"
        anchors.centerIn: parent
        width: parent.width - Units.gu(4)
        visible: view.parsed.lines.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: view.status === "searching" ? "Looking for lyrics…"
            : view.status === "instrumental" ? "Instrumental"
            : view.status === "failed" ? "Could not reach LRCLIB.\nTap to try again."
            : view.ownOnly ? "No lyrics for this song.\nPut them in its tags, or in a .lrc file of the same name beside it."
            : "No lyrics found for this song."
        color: view.theme.darkSecondaryText
        font.pixelSize: view.theme.fontSmall
        MouseArea {
            anchors.fill: parent
            anchors.margins: -Units.gu(2)
            enabled: view.status === "failed" && view.parsed.lines.length === 0
            onClicked: view.retryRequested()
        }
    }

    Text {
        objectName: "lyricsCredit"
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        visible: view.source !== "" && view.parsed.lines.length > 0
        text: "Lyrics from " + view.source
        color: view.theme.darkFaintText
        font.pixelSize: view.theme.fontTiny
    }
}
