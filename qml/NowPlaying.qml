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

import "components"
import "js/Art.js" as Art
import "js/Library.js" as Library
import "js/Streaming.js" as Streaming

/*
 * Now Playing: the cover large, the track, where it is, and every control.
 * Swipe the cover sideways for the next or previous track; tap its left or
 * right edge for the same, its middle to play or pause (as Music Player
 * Remix had it); hold Previous or Next to rewind or fast-forward, faster
 * the longer they are held. Swipe down or use the back gesture to go back
 * to the library.
 * Cover and controls sit side by side when the window is wider than tall.
 */
Rectangle {
    id: np

    property var player
    property var theme
    property var stats
    property var sleepTimer
    property bool showLyrics: false
    property string lyricsText: ""
    // Where they came from: "" the song itself (tags, .lrc), "LRCLIB" looked up.
    property string lyricsSource: ""
    // "searching", "found", "instrumental", "none" or "failed".
    property string lyricsStatus: "none"
    // About the artist in the cover's place (ArtistView), instead of lyrics.
    property bool showArtist: false
    property var artistInfo: null
    // "searching", "found", "none", "failed" or "off".
    property string artistStatus: "none"

    signal closeRequested()

    readonly property var track: player ? player.current : null
    // { format, formats } of a streamed track whose service has a choice.
    readonly property var format: player ? player.currentFormat : null
    readonly property bool landscape: width >= height
    readonly property bool favorite: track !== null && stats.revision >= 0 && stats.isFavorite(track.path)
    // Who to look up: not a streamed track's service, standing in for an
    // artist it did not give (js/Streaming.js), nor the library's "Unknown
    // Artist".
    readonly property string artistName: {
        if (!track)
            return "";
        var name = track.remote ? Streaming.artistOf(track, appWindow.streaming.providerName(track.provider))
                                : String(track.artist || track.albumArtist || "");
        return name === Library.unknownArtist ? "" : name;
    }

    color: theme.darkBackground

    onTrackChanged: if (showLyrics) loadLyrics()
    onShowLyricsChanged: {
        if (showLyrics) {
            showArtist = false;
            loadLyrics();
        }
    }
    onArtistNameChanged: if (showArtist) loadArtist()
    onShowArtistChanged: {
        if (showArtist) {
            showLyrics = false;
            loadArtist();
        }
    }

    // Who the artist is, looked up (ArtistLookup).
    function loadArtist() {
        var name = artistName;
        artistInfo = null;
        if (name === "") {
            artistStatus = "none";
            return;
        }
        if (!appWindow.artistLookup.enabled) {
            artistStatus = "off";
            return;
        }
        artistStatus = "searching";
        appWindow.artistLookup.find(name, function(info, failed) {
            // Another artist by the time the answer came.
            if (np.artistName !== name)
                return;
            np.artistInfo = info;
            np.artistStatus = info ? "found" : (failed ? "failed" : "none");
        });
    }

    // The song's own lyrics; failing those, LRCLIB's (LyricsLookup).
    function loadLyrics() {
        var t = track;
        var own = t && !t.remote ? (appWindow.library.tagReader.read(t.path).lyrics || "") : "";
        lyricsText = own;
        lyricsSource = "";
        lyricsStatus = own !== "" ? "found" : "none";
        if (own !== "" || !t || !appWindow.lyricsLookup.enabled)
            return;
        lyricsStatus = "searching";
        appWindow.lyricsLookup.find(t, function(result, failed) {
            // Another song by the time the answer came.
            if (!np.track || np.track.path !== t.path)
                return;
            if (!result) {
                np.lyricsStatus = failed ? "failed" : "none";
                return;
            }
            np.lyricsText = result.text;
            np.lyricsSource = result.instrumental ? "" : "LRCLIB";
            np.lyricsStatus = result.instrumental ? "instrumental" : "found";
        });
    }

    // The cover, blurred by scaling a tiny copy up, behind everything.
    Image {
        anchors.fill: parent
        source: np.track ? Art.source(np.track.path, np.track.album, np.track.artUrl) : ""
        sourceSize.width: 24
        sourceSize.height: 24
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        opacity: 0.45
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#99000000" }
            GradientStop { position: 0.6; color: "#dd000000" }
            GradientStop { position: 1.0; color: "#f2000000" }
        }
    }

    // Swallow touches, so nothing below reacts.
    MouseArea { anchors.fill: parent }

    /*
     * Held Previous / Next: steps through the track, each step longer the
     * longer the key is held - 3 s, then 15, 30, 60 - as Music Player
     * Remix did it. The click that ends the hold is not a skip.
     */
    Timer {
        id: seeker
        property int direction: 0
        property int steps: 0
        property bool justEnded: false
        interval: 400
        repeat: true
        function begin(d) {
            direction = d;
            steps = 0;
            start();
            triggered();
        }
        function end() {
            if (running) {
                stop();
                justEnded = true;
                endGuard.restart();
            }
        }
        onTriggered: {
            var step = steps < 4 ? 3000 : (steps < 10 ? 15000 : (steps < 20 ? 30000 : 60000));
            steps++;
            np.player.seek(Math.max(0, np.player.position + direction * step));
        }
    }
    // The release after a hold also clicks; this keeps that click from skipping.
    Timer {
        id: endGuard
        interval: 300
        onTriggered: seeker.justEnded = false
    }

    // --- top bar ---------------------------------------------------------
    Item {
        id: topBar
        width: parent.width
        height: Units.gu(6.5)

        IconButton {
            id: closeButton
            objectName: "closeNowPlaying"
            anchors.left: parent.left
            anchors.leftMargin: Units.gu(0.5)
            anchors.verticalCenter: parent.verticalCenter
            image: "down"
            label: "Close"
            accent: np.theme.accent
            onClicked: np.closeRequested()
        }
        Column {
            anchors.left: closeButton.right
            anchors.right: menuButton.left
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "NOW PLAYING"
                color: np.theme.darkSecondaryText
                font.pixelSize: np.theme.fontTiny
                font.letterSpacing: 1
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: np.track ? np.track.album : ""
                color: np.theme.darkText
                font.pixelSize: np.theme.fontSmall
                elide: Text.ElideRight
                MouseArea {
                    anchors.fill: parent
                    onClicked: appWindow.openAlbumOf(np.track)
                }
            }
        }
        IconButton {
            id: menuButton
            anchors.right: parent.right
            anchors.rightMargin: Units.gu(0.5)
            anchors.verticalCenter: parent.verticalCenter
            image: "more"
            label: "More"
            accent: np.theme.accent
            onClicked: appWindow.songMenu(np.track, { nowPlaying: true })
        }
    }

    // --- cover or lyrics -------------------------------------------------
    Item {
        id: artArea
        anchors.top: topBar.bottom
        anchors.left: parent.left
        width: np.landscape ? parent.width * 0.5 : parent.width
        height: np.landscape ? parent.height - topBar.height : parent.height - topBar.height - controls.height

        Cover {

            onLight: false
            id: bigCover
            objectName: "nowPlayingCover"
            readonly property real coverSize: Math.max(Units.gu(10), Math.min(parent.width - Units.gu(4), parent.height - Units.gu(3)))
            width: coverSize
            height: coverSize
            x: (parent.width - width) / 2 + swipe.offset
            anchors.verticalCenter: parent.verticalCenter
            visible: !np.showLyrics && !np.showArtist
            path: np.track ? np.track.path : ""
            album: np.track ? np.track.album : ""
            artUrl: np.track && np.track.artUrl ? np.track.artUrl : ""
            radius: Units.gu(1)

            MouseArea {
                id: swipe
                anchors.fill: parent
                property real startX: 0
                property real startY: 0
                property real offset: 0
                onPressed: function(event) { startX = event.x; startY = event.y; }
                onPositionChanged: function(event) {
                    var dx = event.x - startX;
                    if (Math.abs(dx) > Units.gu(1))
                        offset = dx * 0.5;
                }
                onReleased: function(event) {
                    var dx = event.x - startX, dy = event.y - startY;
                    offset = 0;
                    if (Math.abs(dx) > Units.gu(8) && Math.abs(dx) > Math.abs(dy))
                        dx < 0 ? np.player.next() : np.player.previous();
                    else if (dy > Units.gu(10) && Math.abs(dy) > Math.abs(dx))
                        np.closeRequested();
                    else if (Math.abs(dx) < Units.gu(2) && Math.abs(dy) < Units.gu(2)) {
                        // Music Player Remix's tap regions: the left edge
                        // goes back, the right edge on, the middle plays
                        // and pauses.
                        if (startX < width * 0.25)
                            np.player.previous();
                        else if (startX > width * 0.75)
                            np.player.next();
                        else
                            np.player.toggle();
                    }
                }
                Behavior on offset { NumberAnimation { duration: 120 } }
            }
        }

        LyricsView {
            anchors.fill: parent
            anchors.margins: Units.gu(1)
            visible: np.showLyrics
            theme: np.theme
            text: np.lyricsText
            source: np.lyricsSource
            status: np.lyricsStatus
            ownOnly: !(np.track && np.track.remote) && !appWindow.lyricsLookup.enabled
            position: np.player ? np.player.position : 0
            onSeekRequested: function(ms) { np.player.seek(ms); }
            onRetryRequested: np.loadLyrics()
        }

        ArtistView {
            objectName: "artistView"
            anchors.fill: parent
            anchors.margins: Units.gu(1)
            visible: np.showArtist
            theme: np.theme
            artist: np.artistName
            info: np.artistInfo
            status: np.artistStatus
            inLibrary: np.showArtist && np.artistName !== "" && !!appWindow.library.artist(np.artistName)
            onLibraryRequested: appWindow.openArtistOf(np.track)
            onRetryRequested: np.loadArtist()
        }
    }

    // --- track, seek bar, buttons -----------------------------------------
    Column {
        id: controls
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Units.gu(1.5)
        anchors.right: parent.right
        width: np.landscape ? parent.width * 0.5 : parent.width
        // Not a conditional top anchor: anchored at both ends once, a
        // Column keeps that height when the anchor goes (turning from
        // landscape to portrait), and its buttons would float up.
        height: np.landscape ? np.height - topBar.height - Units.gu(1.5) : implicitHeight
        spacing: Units.gu(1)
        // The buttons' size: their usual one, smaller where the column is
        // narrow (beside the cover on the Q25's square) so all five fit.
        readonly property real btn: Math.min(Math.max(Units.gu(5.5), 54), (width - Units.gu(2)) / 6.8)
        topPadding: np.landscape ? Math.max(0, (height - (implicitHeight - topPadding)) / 2) : 0

        Item {
            width: parent.width
            height: titleCol.implicitHeight

            Column {
                id: titleCol
                anchors.left: parent.left
                anchors.leftMargin: controls.width < Units.gu(45) ? Units.gu(1.5) : Units.gu(2.5)
                anchors.right: heart.left
                spacing: Units.gu(0.3)
                Text {
                    objectName: "nowPlayingTitle"
                    width: parent.width
                    text: np.track ? np.track.title : ""
                    color: np.theme.darkText
                    font.pixelSize: np.theme.fontLarge
                    font.weight: Font.DemiBold
                    // Two lines before eliding: beside the cover there is
                    // only half the width.
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: np.track ? np.track.artist : ""
                    color: np.theme.accent
                    font.pixelSize: np.theme.fontMedium
                    elide: Text.ElideRight
                    MouseArea {
                        anchors.fill: parent
                        onClicked: appWindow.openArtistOf(np.track)
                    }
                }
            }
            IconButton {
                id: heart
                objectName: "favoriteButton"
                anchors.right: parent.right
                anchors.rightMargin: Units.gu(1.5)
                anchors.verticalCenter: parent.verticalCenter
                image: np.favorite ? "heart" : "heart-outline"
                label: np.favorite ? "Unfavorite" : "Favorite"
                accent: np.theme.accent
                onClicked: np.stats.setFavorite(np.track.path, !np.favorite)
            }
        }

        SeekBar {
            objectName: "seekBar"
            x: Units.gu(2.5)
            width: parent.width - Units.gu(5)
            position: np.player ? np.player.position : 0
            duration: np.player ? np.player.duration : 0
            textColor: np.theme.darkSecondaryText
            onSeekRequested: function(ms) { np.player.seek(ms); }

            // The streamed track's format, between the times; a tap offers
            // the others when there are any.
            Rectangle {
                id: formatBadge
                objectName: "formatBadge"
                readonly property bool switchable: !!(np.format && np.format.formats.length > 1)
                visible: np.format !== null
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: formatRow.implicitWidth + Units.gu(1.6)
                height: formatText.implicitHeight + Units.gu(0.4)
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: switchable ? np.theme.accent : np.theme.darkSecondaryText
                Row {
                    id: formatRow
                    anchors.centerIn: parent
                    spacing: Units.gu(0.3)
                    Text {
                        id: formatText
                        objectName: "formatText"
                        text: np.format ? np.format.format : ""
                        color: formatBadge.switchable ? np.theme.darkText : np.theme.darkSecondaryText
                        font.pixelSize: np.theme.fontTiny
                    }
                    // The device fonts have no ▾.
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: formatBadge.switchable
                        source: Qt.resolvedUrl("images/down.svg")
                        sourceSize.width: formatText.font.pixelSize
                        sourceSize.height: formatText.font.pixelSize
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    // A finger-sized target around the small badge.
                    anchors.margins: -Units.gu(1)
                    enabled: formatBadge.switchable
                    onClicked: appWindow.chooseFormat()
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: controls.width < Units.gu(45) ? controls.btn * 0.1 : Units.gu(2)

            IconButton {
                objectName: "shuffleButton"
                anchors.verticalCenter: parent.verticalCenter
                width: controls.btn
                height: controls.btn
                image: "shuffle"
                label: "Shuffle"
                active: !!(np.player && np.player.shuffle)
                accent: np.theme.accent
                onClicked: np.player.setShuffle(!np.player.shuffle)
            }
            IconButton {
                objectName: "previousButton"
                anchors.verticalCenter: parent.verticalCenter
                width: controls.btn
                height: controls.btn
                image: "previous"
                label: "Previous"
                iconSize: controls.btn * 0.62
                accent: np.theme.accent
                onClicked: if (!seeker.running && !seeker.justEnded) np.player.previous()
                onPressAndHold: seeker.begin(-1)
                onReleased: seeker.end()
                onCanceled: seeker.end()
            }
            IconButton {
                objectName: "playPauseButton"
                anchors.verticalCenter: parent.verticalCenter
                width: controls.btn * 1.5
                height: width
                image: np.player && np.player.playing ? "pause" : "play"
                label: np.player && np.player.playing ? "Pause" : "Play"
                iconSize: controls.btn * 0.72
                filled: true
                accent: np.theme.accent
                onClicked: np.player.toggle()
            }
            IconButton {
                objectName: "nextButton"
                anchors.verticalCenter: parent.verticalCenter
                width: controls.btn
                height: controls.btn
                image: "next"
                label: "Next"
                iconSize: controls.btn * 0.62
                enabled: !!(np.player && np.player.hasNext)
                accent: np.theme.accent
                onClicked: if (!seeker.running && !seeker.justEnded) np.player.next()
                onPressAndHold: seeker.begin(1)
                onReleased: seeker.end()
                onCanceled: seeker.end()
            }
            IconButton {
                objectName: "repeatButton"
                anchors.verticalCenter: parent.verticalCenter
                width: controls.btn
                height: controls.btn
                image: np.player && np.player.repeat === "one" ? "repeat-one" : "repeat"
                label: "Repeat " + (np.player ? np.player.repeat : "off")
                active: !!(np.player && np.player.repeat !== "off")
                accent: np.theme.accent
                onClicked: np.player.cycleRepeat()
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: controls.width < Units.gu(45) ? controls.btn * 0.25 : Units.gu(3)

            Item {
                width: controls.btn * 1.25
                height: controls.btn
                IconButton {
                    objectName: "sleepButton"
                    anchors.centerIn: parent
                    width: controls.btn
                    height: controls.btn
                    image: "sleep"
                    label: "Sleep timer"
                    iconSize: Units.gu(2.6)
                    active: !!(np.sleepTimer && np.sleepTimer.running)
                    accent: np.theme.accent
                    onClicked: appWindow.chooseSleepTimer()
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: -Units.gu(0.5)
                    visible: !!(np.sleepTimer && np.sleepTimer.running)
                    text: np.sleepTimer ? np.sleepTimer.remainingText : ""
                    color: np.theme.accent
                    font.pixelSize: np.theme.fontTiny
                }
            }
            IconButton {
                objectName: "lyricsButton"
                width: controls.btn
                height: controls.btn
                image: "lyrics"
                label: "Lyrics"
                iconSize: Units.gu(2.6)
                active: np.showLyrics
                accent: np.theme.accent
                onClicked: np.showLyrics = !np.showLyrics
            }
            IconButton {
                objectName: "artistButton"
                width: controls.btn
                height: controls.btn
                image: "artist"
                label: "About the artist"
                iconSize: Units.gu(2.6)
                active: np.showArtist
                accent: np.theme.accent
                onClicked: np.showArtist = !np.showArtist
            }
            Item {
                width: controls.btn * 1.25
                height: controls.btn
                IconButton {
                    objectName: "speedButton"
                    anchors.centerIn: parent
                    width: controls.btn
                    height: controls.btn
                    image: "speed"
                    label: "Speed"
                    iconSize: Units.gu(2.6)
                    active: !!(np.player && np.player.rate !== 1)
                    accent: np.theme.accent
                    onClicked: appWindow.chooseSpeed()
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: -Units.gu(0.5)
                    visible: !!(np.player && np.player.rate !== 1)
                    text: np.player ? np.player.rate + "×" : ""
                    color: np.theme.accent
                    font.pixelSize: np.theme.fontTiny
                }
            }
            IconButton {
                objectName: "queueButton"
                width: controls.btn
                height: controls.btn
                image: "queue"
                label: "Up next"
                iconSize: Units.gu(2.6)
                accent: np.theme.accent
                onClicked: appWindow.openQueue()
            }
        }
    }
}
