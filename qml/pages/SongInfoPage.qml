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

import LunaNext.Common 0.1
import LuneOS.Forms 1.0

import "../js/Library.js" as Library

/* Everything the file's tags and the play counts say about a song. */
AppPage {
    id: page

    objectName: "songInfoPage"
    title: "Song Info"

    property var song: null
    readonly property var tags: song ? appWindow.library.tagReader.read(song.path) : ({})
    readonly property var stat: song && appWindow.stats.revision >= 0 ? appWindow.stats.get(song.path) : null

    function gainText(gain) {
        return gain === undefined ? "" : (gain > 0 ? "+" : "") + Number(gain).toFixed(2) + " dB";
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
                title: "Song"
                LabelAndValue { label: "Title"; value: page.tags.title || (page.song ? page.song.title : "") }
                LabelAndValue { label: "Artist"; value: page.tags.artist || ""; visible: value !== "" }
                LabelAndValue { label: "Album"; value: page.tags.album || ""; visible: value !== "" }
                LabelAndValue { label: "Album artist"; value: page.tags.albumArtist || ""; visible: value !== "" }
                LabelAndValue { label: "Composer"; value: page.tags.composer || ""; visible: value !== "" }
                LabelAndValue { label: "Genre"; value: page.tags.genre || ""; visible: value !== "" }
                LabelAndValue { label: "Year"; value: page.tags.year > 0 ? page.tags.year : ""; visible: value !== "" }
                LabelAndValue {
                    label: "Track"
                    value: page.tags.track > 0 ? page.tags.track + (page.tags.trackTotal > 0 ? " of " + page.tags.trackTotal : "") : ""
                    visible: value !== ""
                }
                LabelAndValue {
                    label: "Disc"
                    value: page.tags.disc > 0 ? page.tags.disc + (page.tags.discTotal > 0 ? " of " + page.tags.discTotal : "") : ""
                    visible: value !== ""
                }
                LabelAndValue { label: "Length"; value: Library.formatDuration(page.tags.duration || 0) }
            }

            FormGroup {
                Layout.fillWidth: true
                title: "File"
                LabelAndValue {
                    label: "Format"
                    value: (page.tags.format || "") + (page.tags.bitrate > 0 ? ", " + page.tags.bitrate + " kbit/s" : "")
                           + (page.tags.sampleRate > 0 ? ", " + (page.tags.sampleRate / 1000) + " kHz" : "")
                           + (page.tags.channels === 1 ? ", mono" : (page.tags.channels === 2 ? ", stereo" : ""))
                }
                LabelAndValue { label: "Size"; value: page.tags.size > 0 ? (page.tags.size / 1048576).toFixed(1) + " MB" : "" }
                LabelAndValue { label: "Track gain"; value: page.gainText(page.tags.trackGain); visible: value !== "" }
                LabelAndValue { label: "Album gain"; value: page.gainText(page.tags.albumGain); visible: value !== "" }
                LabelAndValue { label: "Lyrics"; value: page.tags.lyrics ? "Yes" : "No" }
            }

            Label {
                Layout.fillWidth: true
                text: page.song ? page.song.path : ""
                wrapMode: Text.WrapAnywhere
                font.pixelSize: FontUtils.sizeToPixels("small")
                color: Colors.secondaryText
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Listening"
                LabelAndValue { label: "Played"; value: page.stat ? Library.plural(page.stat.playCount || 0, "time", "times") : "Never" }
                LabelAndValue {
                    label: "Last played"
                    value: page.stat && page.stat.lastPlayed > 0 ? Qt.formatDateTime(new Date(page.stat.lastPlayed), "d MMM yyyy, hh:mm") : "Never"
                }
                LabelAndValue { label: "Skipped"; value: page.stat ? Library.plural(page.stat.skipCount || 0, "time", "times") : "Never" }
            }
        }
    }
}
