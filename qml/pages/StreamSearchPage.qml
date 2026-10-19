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

/*
 * Search one streaming service: its tracks as they come, to play, queue,
 * favourite or put in a playlist like any song.
 */
Item {
    id: page

    property string providerId: ""
    property string title: appWindow.streaming.providerName(providerId)
    property alias text: field.text
    readonly property var theme: appWindow.theme

    property var results: []
    property bool searching: false
    property string error: ""
    property int _serial: 0

    Component.onCompleted: field.forceActiveFocus()

    function search() {
        var serial = ++_serial;
        error = "";
        if (field.text.trim() === "") {
            results = [];
            searching = false;
            return;
        }
        searching = true;
        appWindow.streaming.search(providerId, field.text, 40, function(tracks, err) {
            if (serial !== page._serial)
                return;
            page.searching = false;
            page.results = tracks;
            page.error = err;
        });
    }

    // Each key would be a request; the service is asked once typing pauses.
    Timer {
        id: debounce
        interval: 600
        onTriggered: page.search()
    }

    // Done typing: a result picked, Enter, or the list scrolled. The keyboard
    // goes with the field's focus.
    function dismissKeyboard() {
        field.focus = false;
        Qt.inputMethod.hide();
    }

    TextField {
        id: field
        objectName: "streamSearchField"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Units.gu(1)
        placeholderText: "Search " + page.title
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: debounce.restart()
        onAccepted: { debounce.stop(); page.search(); page.dismissKeyboard(); }
    }

    ListView {
        id: list
        objectName: "streamResults"
        anchors.top: field.bottom
        anchors.topMargin: Units.gu(1)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: page.results
        onMovementStarted: page.dismissKeyboard()
        delegate: SongRow {
            required property var modelData
            required property int index
            song: modelData
            theme: page.theme
            subtitle: modelData.artist + (modelData.album && modelData.album !== modelData.artist ? " — " + modelData.album : "")
            playing: appWindow.player.current !== null && appWindow.player.current.path === modelData.path
            onClicked: { page.dismissKeyboard(); appWindow.player.playTracks(page.results, index, false); }
            onMenuRequested: { page.dismissKeyboard(); appWindow.songMenu(modelData, null); }
        }
    }

    BusyIndicator {
        anchors.centerIn: list
        running: page.searching
        visible: page.searching
    }

    StatusPanel {
        anchors.fill: list
        theme: page.theme
        visible: !page.searching && page.results.length === 0 && (page.error !== "" || field.text.trim() !== "")
        icon: "stream"
        title: page.error !== "" ? "The search did not work" : "Nothing found"
        text: page.error
    }
}
