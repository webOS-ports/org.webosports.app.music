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
 * Finding a podcast: by name in the podcast directory, or by the address
 * of its feed, typed or pasted. A podcast found opens its page, where it
 * can be listened to and subscribed to.
 */
Item {
    id: page

    property string title: "Find Podcasts"
    property alias text: field.text
    readonly property var theme: appWindow.theme
    readonly property var store: appWindow.podcasts

    property var results: []
    property bool searching: false
    property string error: ""
    property int _serial: 0
    readonly property string feedAddress: Podcasts.feedAddressOf(field.text)

    Component.onCompleted: field.forceActiveFocus()

    function search() {
        var serial = ++_serial;
        error = "";
        var q = field.text.trim();
        if (q === "" || feedAddress !== "") {
            results = [];
            searching = false;
            return;
        }
        searching = true;
        store.search(q, function(list, err) {
            if (serial !== page._serial)
                return;
            page.searching = false;
            page.results = list;
            page.error = err;
        });
    }

    Timer {
        id: debounce
        interval: 600
        onTriggered: page.search()
    }

    function dismissKeyboard() {
        field.focus = false;
        Qt.inputMethod.hide();
    }

    TextField {
        id: field
        objectName: "podcastSearchField"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Units.gu(1)
        placeholderText: "Podcast name, or its feed's address"
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        onTextChanged: debounce.restart()
        onAccepted: {
            debounce.stop();
            if (page.feedAddress !== "")
                appWindow.openPodcast({ url: page.feedAddress });
            else
                page.search();
            page.dismissKeyboard();
        }
    }

    ListView {
        id: list
        objectName: "podcastResults"
        anchors.top: field.bottom
        anchors.topMargin: Units.gu(1)
        anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        model: page.feedAddress !== "" ? [{ feed: page.feedAddress }] : page.results
        onMovementStarted: page.dismissKeyboard()
        delegate: ListRow {
            required property var modelData
            theme: page.theme
            readonly property string subscribedId: modelData.feed ? "" : page.store.subscribedId(modelData.url)
            title: modelData.feed ? "Open this feed" : (modelData.title || "")
            subtitle: modelData.feed ? modelData.feed
                      : (subscribedId !== "" ? "Subscribed · " : "") + (modelData.author || "")
            icon: "podcast"
            artUrl: modelData.image || ""
            onClicked: {
                page.dismissKeyboard();
                if (modelData.feed)
                    appWindow.openPodcast({ url: modelData.feed });
                else if (subscribedId !== "")
                    appWindow.openPodcast({ id: subscribedId });
                else
                    appWindow.openPodcast(modelData);
            }
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
        visible: !page.searching && page.feedAddress === "" && page.results.length === 0
        icon: "podcast"
        title: page.error !== "" ? "The search did not work"
               : field.text.trim() !== "" ? "Nothing found" : "Find a podcast"
        text: page.error !== "" ? page.error
              : field.text.trim() !== "" ? "" : "Search the webOS Archive podcast directory by name, or paste the address of a podcast's feed."
    }
}
