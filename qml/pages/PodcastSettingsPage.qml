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
import QtQuick.Layouts

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import "../js/Podcasts.js" as Podcasts

/*
 * How podcasts are kept: how often the feeds are read, what is downloaded
 * by itself and when, when downloads of played episodes go, and moving the
 * list of podcasts to and from another app (OPML).
 */
AppPage {
    id: page

    title: "Podcast Settings"

    readonly property var store: appWindow.podcasts
    readonly property var settings: store.settings
    property bool importing: false

    function importFrom(what) {
        importing = true;
        store.importOpml(what, function(result, error) {
            page.importing = false;
            if (!result) {
                appWindow.notify(error || "The list cannot be imported.");
                return;
            }
            appWindow.notify(Podcasts.importSummary(result));
        });
    }

    function chooseFile() {
        store.opmlFiles(function(files) {
            if (files.length === 0) {
                appWindow.notify("No OPML files found. Copy one to the device first, or import it from its address.");
                return;
            }
            appWindow.sheet.show("Import podcasts", files.map(function(f) {
                return { label: f.name, action: function() { page.importFrom({ path: f.path }); } };
            }), "OPML files on this device");
        });
    }

    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight + Units.gu(2)
        clip: true

        ColumnLayout {
            id: content

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            spacing: Units.gu(1)

            FormGroup {
                Layout.fillWidth: true
                title: "New episodes"

                LabelAndSelector {
                    objectName: "refreshSelector"
                    label: "Look for them"
                    model: Podcasts.refreshChoices.map(Podcasts.refreshLabel)
                    values: Podcasts.refreshChoices
                    value: page.settings.refreshHours
                    onChosen: (v) => page.store.saveSettings({ refreshHours: v })
                }
                LabelAndSwitch {
                    objectName: "notifySwitch"
                    label: "Tell me about new episodes"
                    checked: page.settings.notify
                    onToggled: page.store.saveSettings({ notify: checked })
                }
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Downloads"

                LabelAndSelector {
                    objectName: "autoDownloadSelector"
                    label: "For new podcasts, download"
                    model: Podcasts.autoDownloadChoices.map(Podcasts.autoDownloadLabel)
                    values: Podcasts.autoDownloadChoices
                    value: page.settings.autoDownload
                    onChosen: (v) => page.store.saveSettings({ autoDownload: v })
                }
                LabelAndSwitch {
                    objectName: "wifiOnlySwitch"
                    label: "Only on Wi-Fi"
                    checked: page.settings.wifiOnly
                    onToggled: page.store.saveSettings({ wifiOnly: checked })
                }
                LabelAndSelector {
                    objectName: "keepSelector"
                    label: "Delete played episodes"
                    model: Podcasts.keepChoices.map(Podcasts.keepLabel)
                    values: Podcasts.keepChoices
                    value: page.settings.keepPlayedDays
                    onChosen: (v) => page.store.saveSettings({ keepPlayedDays: v })
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "The music streaming service looks for new episodes and downloads them also while Music is closed. Each podcast's menu sets how many of its newest episodes it downloads by itself. Downloads are in the podcasts folder of the internal storage, so they can be copied over USB too; downloads you start yourself are not limited to Wi-Fi."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Import and export"

                Button {
                    objectName: "importFileButton"
                    Layout.fillWidth: true
                    text: page.importing ? "Importing…" : "Import from a File…"
                    enabled: !page.importing
                    LuneOSButton.mainColor: LuneOSButton.secondaryColor
                    onClicked: page.chooseFile()
                }
                LabelAndTextField {
                    id: addressField
                    objectName: "importAddressField"
                    Layout.fillWidth: true
                    label: "From an address"
                    placeholderText: "https://…/podcasts.opml"
                    inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    onCommitted: (text) => {
                        if (/^https?:\/\/\S+$/i.test(text.trim())) {
                            page.importFrom({ url: text.trim() });
                            addressField.text = "";
                        } else if (text.trim() !== "") {
                            appWindow.notify("That is not a web address.");
                        }
                    }
                }
                Button {
                    objectName: "exportButton"
                    Layout.fillWidth: true
                    text: "Export"
                    enabled: page.store.podcasts.length > 0
                    LuneOSButton.mainColor: LuneOSButton.secondaryColor
                    onClicked: page.store.exportOpml(function(path, error) {
                        appWindow.notify(path !== "" ? "Saved as " + path + "." : (error || "The list cannot be saved."));
                    })
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "Most podcast apps export their podcasts as an OPML file. Import one to subscribe to them all here; Export writes podcasts.opml to the podcasts folder, for another app or another device."
            }
        }
    }
}
