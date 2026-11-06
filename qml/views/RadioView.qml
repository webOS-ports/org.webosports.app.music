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
import "../js/FmRadio.js" as Fm
import "../js/Streaming.js" as Streaming

/*
 * Radio, in a tab of its own. FM first, on a device with a tuner: the
 * station it is on (seek, a step either way, on and off), the stations the
 * last scan found and a scan; the radio plays through the player like any
 * station, so Now Playing, the dashboard and the headset's keys work for it.
 * Then Internet Radio while its account is in Accounts: searching for a
 * station, the user's own station lists and Radio Browser's (Most played,
 * Jazz...). The favourite stations, FM and Internet, between the two.
 */
Item {
    id: view

    property var theme: appWindow.theme

    readonly property var lists: {
        var s = appWindow.streaming.servicePlaylists.filter(function(x) { return x.provider === "radio"; })[0];
        return s ? s.playlists : [];
    }

    // --- FM ------------------------------------------------------------------
    readonly property var fm: appWindow.fmRadio
    readonly property var player: appWindow.player
    // The last scan's stations, as kept (and as the user trimmed them, to
    // none at all), else the ones the radio found before this app saw a
    // scan.
    readonly property var fmStations: {
        if (appWindow.prefs.fmStations === "")
            return fm.stations;
        try {
            return Fm.stationList(JSON.parse(appWindow.prefs.fmStations));
        } catch (e) {
            return fm.stations;
        }
    }
    readonly property bool fmPlaying: player.playing && player.current !== null && Fm.isFm(player.current.path)
    // The station shown: the one on, else the last one played here, else
    // where the service last had the radio.
    readonly property int fmTuned: fm.powered ? fm.frequency
                                   : appWindow.prefs.fmFrequency > 0 ? appWindow.prefs.fmFrequency
                                   : Fm.valid(fm.frequency, fm.band) ? fm.frequency : fm.band.min
    property bool fmScanning: false
    // Read here so that the names below follow the preferences.
    readonly property string _fmNames: appWindow.prefs.fmNames + appWindow.prefs.fmOwnNames
    // The station shown: the user's name for it, else what it calls itself
    // while on it, else the name it sent before, else "".
    readonly property string fmTunedName: {
        var own = Fm.nameOf(fmTuned, Fm.namesFrom(appWindow.prefs.fmOwnNames), null);
        if (own !== "")
            return own;
        if (fm.powered && fm.frequency === fmTuned && fm.rdsName !== "")
            return fm.rdsName;
        return fmNameOf(fmTuned);
    }
    readonly property string fmTunedText: fm.powered && fm.frequency === fmTuned ? fm.rdsText : ""

    function fmNameOf(khz) {
        _fmNames;
        return appWindow.fmName(khz);
    }

    function playFm(khz) {
        appWindow.prefs.fmFrequency = khz;
        player.playTracks([Fm.track(khz, appWindow.fmName(khz))], 0, false);
    }

    function toggleFm() {
        if (fmPlaying)
            player.pause();
        else
            playFm(fmTuned);
    }

    // A channel either way: playing on there, or only remembered.
    function stepFm(dir) {
        var khz = Fm.step(fmTuned, dir, fm.band);
        if (fmPlaying)
            playFm(khz);
        else
            appWindow.prefs.fmFrequency = khz;
    }

    // The next station: the radio comes on for it if it was off.
    function seekFm(dir) {
        if (!fmPlaying)
            playFm(fmTuned);
        fm.seek(dir, function(ok, khz) {
            if (ok && khz > 0)
                view.playFm(khz);
        });
    }

    function scanFm() {
        if (fmScanning)
            return;
        fmScanning = true;
        fm.scan(function(ok, stations) {
            view.fmScanning = false;
            if (ok) {
                appWindow.prefs.fmStations = JSON.stringify(stations);
                // Scanned while on: the service names them only after a
                // scan with the radio off, so the app asks once it is.
                if (view.fm.powered)
                    appWindow.fmNamesAsked = false;
            }
        });
    }

    readonly property var rows: {
        appWindow.stats.revision;
        var out = [];
        var favs = appWindow.smartTracks("favoriteStations");
        var favourites = function() {
            if (favs.length === 0)
                return;
            out.push({ kind: "header", name: "FAVORITE STATIONS" });
            favs.forEach(function(t, i) { out.push({ kind: "station", track: t, index: i }); });
        };
        // With FM: the tuner and its stations, the favourites (of both),
        // then Internet Radio under a heading of its own. Without, Internet
        // Radio is the whole tab and starts with its search.
        if (fm.available) {
            out.push({ kind: "fmTuner" });
            out.push({ kind: "header", name: "FM STATIONS" });
            fmStations.forEach(function(k) { out.push({ kind: "fmStation", khz: k }); });
            out.push({ kind: "fmScan" });
            favourites();
            if (!appWindow.hasInternetRadio)
                return out;
            out.push({ kind: "header", name: "INTERNET RADIO" });
            out.push({ kind: "search" });
        } else {
            out.push({ kind: "search" });
            favourites();
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
            sourceComponent: modelData.kind === "header" ? headerRow
                             : modelData.kind === "fmTuner" ? fmTuner : itemRow
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
            readonly property bool fmOn: modelData.kind === "fmStation" && view.fmPlaying
                                         && view.fm.frequency === modelData.khz
            title: modelData.kind === "search" ? "Search stations"
                   : modelData.kind === "fmStation" ? (view.fmNameOf(modelData.khz) || Fm.title(modelData.khz))
                   : modelData.kind === "fmScan" ? (view.fmScanning ? "Scanning..." : "Scan for stations")
                   : track ? track.title : playlist ? playlist.name : ""
            subtitle: modelData.kind === "search" ? "Tens of thousands, from Radio Browser"
                      : modelData.kind === "fmStation" ? [view.fmNameOf(modelData.khz) !== "" ? Fm.title(modelData.khz) : "",
                                                          fmOn ? "Playing" : ""].filter(function(x) { return x !== ""; }).join(" · ")
                      : modelData.kind === "fmScan" ? (view.fmScanning ? "The whole band takes about ten seconds"
                                                       : view.fmStations.length > 0 ? "Finds the stations here again"
                                                       : "Finds every station you can receive here")
                      : track ? (track.artist || "")
                      // Under RADIO BROWSER, nothing more to say.
                      : playlist ? (playlist.tracks > 0 ? Streaming.countOf("radio", playlist.tracks) : "") : ""
            icon: modelData.kind === "search" ? "search"
                  : modelData.kind === "fmStation" ? (fmOn ? "pause" : "stream")
                  : modelData.kind === "fmScan" ? "search"
                  : track ? "stream" : "playlist"
            artUrl: track ? (track.artUrl || "") : playlist ? (playlist.thumbnail || "") : ""
            showMenu: modelData.kind === "station" || modelData.kind === "fmStation"
            swipeToDelete: modelData.kind === "fmStation"
            onSwipeDeleted: appWindow.fmRemoveStation(modelData.khz)
            onClicked: {
                if (modelData.kind === "search")
                    appWindow.openStreamingSearch("radio");
                else if (modelData.kind === "fmStation")
                    fmOn ? view.player.pause() : view.playFm(modelData.khz);
                else if (modelData.kind === "fmScan")
                    view.scanFm();
                else if (track)
                    appWindow.player.playTracks([track], 0, false);
                else if (playlist)
                    appWindow.openServicePlaylist("radio", playlist);
            }
            onMenuRequested: {
                if (modelData.kind === "fmStation")
                    appWindow.fmStationMenu(modelData.khz);
                else
                    appWindow.songMenu(track, null);
            }
        }
    }

    /* The station FM is on: its frequency, how well it comes in, and the
     * keys - seek down, a channel down, on/off, a channel up, seek up. */
    Component {
        id: fmTuner
        Item {
            id: card
            height: Units.gu(18.5) + (nameLine.visible ? nameLine.height : 0) + (textLine.visible ? textLine.height : 0)

            readonly property string state_: !view.fm.powered ? (view.fmScanning ? "Scanning..."
                                                                 : view.fm.busy === "naming" ? "Off · finding station names..."
                                                                 : "Off")
                                             : view.fm.busy === "seeking" ? "Seeking..."
                                             : view.fm.busy === "scanning" ? "Scanning..."
                                             : view.fm.rssi === null ? ""
                                             : Fm.bars(view.fm.rssi) === 0 ? "No signal: the headphones are the antenna"
                                             : Fm.bars(view.fm.rssi) < 3 ? "Weak signal: the headphones are the antenna"
                                             : "Good signal"

            Text {
                id: freq
                objectName: "fmFrequency"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Units.gu(1.5)
                text: Fm.mhz(view.fmTuned)
                color: view.fm.powered ? view.theme.text : view.theme.secondaryText
                font.pixelSize: Units.gu(5.5)
                font.weight: Font.Light
            }
            Text {
                anchors.left: freq.right
                anchors.leftMargin: Units.gu(0.5)
                anchors.baseline: freq.baseline
                text: "MHz"
                color: view.theme.secondaryText
                font.pixelSize: view.theme.fontSmall
            }
            // How strong: four bars, lit as the RSSI allows.
            Row {
                anchors.right: freq.left
                anchors.rightMargin: Units.gu(1.5)
                anchors.bottom: freq.baseline
                spacing: Units.gu(0.3)
                visible: view.fm.powered
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: Units.gu(0.6)
                        height: Units.gu(0.8) * (index + 1)
                        anchors.bottom: parent.bottom
                        color: index < Fm.bars(view.fm.rssi) ? view.theme.accentOnLight : view.theme.dividerLight
                    }
                }
            }
            // Its name, as it sends it (or as the user named it).
            Text {
                id: nameLine
                objectName: "fmName"
                anchors.top: freq.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * view.theme.margin
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: text !== ""
                height: visible ? implicitHeight : 0
                text: view.fmTunedName
                color: view.theme.text
                font.pixelSize: view.theme.fontMedium
            }
            // What it says it is playing (its RadioText).
            Text {
                id: textLine
                objectName: "fmText"
                anchors.top: nameLine.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * view.theme.margin
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: text !== ""
                height: visible ? implicitHeight : 0
                text: view.fmTunedText
                color: view.theme.secondaryText
                font.pixelSize: view.theme.fontSmall
            }
            Text {
                id: stateLine
                objectName: "fmState"
                anchors.top: textLine.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * view.theme.margin
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.state_
                color: view.theme.secondaryText
                font.pixelSize: view.theme.fontTiny
            }
            Row {
                anchors.top: stateLine.bottom
                anchors.topMargin: Units.gu(1)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Units.gu(1)
                IconButton {
                    objectName: "fmSeekDown"
                    onLight: true
                    image: "previous"
                    label: "Previous station"
                    onClicked: view.seekFm(-1)
                }
                IconButton {
                    objectName: "fmStepDown"
                    onLight: true
                    image: "back"
                    label: "Down 0.1 MHz"
                    onClicked: view.stepFm(-1)
                }
                IconButton {
                    objectName: "fmPlay"
                    onLight: true
                    filled: true
                    accent: view.theme.accent
                    image: view.fmPlaying ? "pause" : "play"
                    label: view.fmPlaying ? "Turn the radio off" : "Turn the radio on"
                    onClicked: view.toggleFm()
                }
                IconButton {
                    objectName: "fmStepUp"
                    onLight: true
                    image: "back"
                    label: "Up 0.1 MHz"
                    rotation: 180
                    onClicked: view.stepFm(1)
                }
                IconButton {
                    objectName: "fmSeekUp"
                    onLight: true
                    image: "next"
                    label: "Next station"
                    onClicked: view.seekFm(1)
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: view.theme.dividerLight
            }
        }
    }
}
