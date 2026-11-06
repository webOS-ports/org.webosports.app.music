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

import QtCore
import LuneOS.Components 1.0

/*
 * The app's preferences. Every property here is saved; play counts,
 * favourites and playlists are in db8, the queue in StateFile.
 */
Settings {
    id: prefs

    // In the app's own file, as every QML app has (LuneOS.Components' AppFiles).
    location: AppFiles.preferencesFile("org.webosports.app.music")
    category: "music"

    // "off", "track", "album" or "auto" (album gain while an album plays in order).
    property string replayGain: "auto"
    property bool preventClipping: true
    // Overlap between songs, in seconds; 0 plays them gapless.
    property int crossfade: 0
    // Audiobooks, podcasts and anything over 20 minutes carry on where they were left.
    property bool resumeLongTracks: true
    property bool pauseOnCall: true
    property bool resumeAfterCall: true
    // Tint the player with the colour of the playing track's cover.
    property bool followArt: true
    // Lyrics from LRCLIB for songs without their own.
    property bool lyricsOnline: true
    // Who the playing artist is, from Wikidata, Wikipedia and Deezer.
    property bool artistOnline: true
    // The streaming format picked per service, as JSON: { "soundcloud": "AAC 96" }.
    property string streamFormats: "{}"

    // FM radio: the last scan's stations (kHz, as JSON; "" before any, so
    // a list trimmed to nothing stays empty) and the last station played,
    // for the Radio tab before the radio is first on.
    property string fmStations: ""
    property int fmFrequency: 0
    // The stations' names, as JSON { "<kHz>": name }: the ones they sent
    // over RDS, and the ones the user gave them, which come first.
    property string fmNames: "{}"
    property string fmOwnNames: "{}"

    property string albumSort: "title"
    property string songSort: "title"
}
