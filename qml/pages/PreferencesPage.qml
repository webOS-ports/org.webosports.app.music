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

/*
 * How music plays: loudness levelling, crossfade, resuming long tracks,
 * phone calls; the player's colours; and the library's caches.
 */
AppPage {
    id: page

    objectName: "preferencesPage"
    title: "Preferences"

    readonly property var prefs: appWindow.prefs

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
                title: "Playback"

                LabelAndSelector {
                    objectName: "replayGainSelector"
                    label: "Volume levelling"
                    model: ["Off", "Automatic", "Track", "Album"]
                    values: ["off", "auto", "track", "album"]
                    value: page.prefs.replayGain
                    onChosen: (v) => page.prefs.replayGain = v
                }
                LabelAndSwitch {
                    label: "Prevent clipping"
                    visible: page.prefs.replayGain !== "off"
                    checked: page.prefs.preventClipping
                    onToggled: page.prefs.preventClipping = checked
                }
                LabelAndSelector {
                    objectName: "crossfadeSelector"
                    label: "Crossfade"
                    model: ["Off (gapless)", "2 seconds", "4 seconds", "6 seconds", "8 seconds", "12 seconds"]
                    values: [0, 2, 4, 6, 8, 12]
                    value: page.prefs.crossfade
                    onChosen: (v) => page.prefs.crossfade = v
                }
                LabelAndSwitch {
                    label: "Resume audiobooks and long tracks"
                    checked: page.prefs.resumeLongTracks
                    onToggled: page.prefs.resumeLongTracks = checked
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "Volume levelling uses the ReplayGain tags most rippers and taggers write, so every song plays about as loud. Automatic levels whole albums when one plays in order and single songs otherwise. Audiobooks, podcasts and tracks of over 20 minutes start again where you left them."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Phone calls"

                LabelAndSwitch {
                    label: "Pause for calls"
                    checked: page.prefs.pauseOnCall
                    onToggled: page.prefs.pauseOnCall = checked
                }
                LabelAndSwitch {
                    label: "Carry on after the call"
                    visible: page.prefs.pauseOnCall
                    checked: page.prefs.resumeAfterCall
                    onToggled: page.prefs.resumeAfterCall = checked
                }
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Appearance"

                LabelAndSwitch {
                    label: "Colours from the album cover"
                    checked: page.prefs.followArt
                    onToggled: page.prefs.followArt = checked
                }
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Lyrics"

                LabelAndSwitch {
                    objectName: "lyricsOnlineSwitch"
                    label: "Look up lyrics online"
                    checked: page.prefs.lyricsOnline
                    onToggled: page.prefs.lyricsOnline = checked
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "For a song without lyrics of its own - every streamed one, and files without lyrics in their tags or a .lrc file beside them - Music asks LRCLIB (lrclib.net), an open lyrics database, sending the song's artist and title."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Artists"

                LabelAndSwitch {
                    objectName: "artistOnlineSwitch"
                    label: "Look up artists online"
                    checked: page.prefs.artistOnline
                    onToggled: page.prefs.artistOnline = checked
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "About the artist, in Now Playing, comes from Wikidata and Wikipedia, and Deezer's public catalogue: Music sends them the artist's name. No account is needed."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Library"

                LabelAndValue {
                    label: "Songs"
                    value: appWindow.library.lib.songs.length
                }
                LabelAndValue {
                    label: "Albums"
                    value: appWindow.library.lib.albums.length
                }
                LabelAndValue {
                    label: "Artists"
                    value: appWindow.library.lib.artists.length
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Units.gu(1)
                Button {
                    Layout.fillWidth: true
                    text: "Reload Library"
                    onClicked: appWindow.library.load()
                }
                Button {
                    Layout.fillWidth: true
                    text: "Forget Covers"
                    onClicked: {
                        appWindow.artCache.clear();
                        appWindow.notify("The covers will be looked up again.");
                    }
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "Music lists what the device's media indexer has found in its internal storage; cards and USB sticks are under Folders. Covers come from the songs' tags or a cover.jpg or folder.jpg beside them."
            }
        }
    }
}
