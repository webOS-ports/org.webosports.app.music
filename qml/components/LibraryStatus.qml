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

/*
 * StatusPanel for the library as a whole, shown over a view while the
 * library has nothing for it.
 */
StatusPanel {
    id: status

    property var library

    readonly property bool needed: library.status !== "ready"

    visible: needed
    busy: library.status === "loading"
    icon: "note"
    title: {
        switch (library.status) {
        case "loading": return "";
        case "empty": return "No music yet";
        case "denied": return "Music needs your permission";
        default: return "Your music cannot be read";
        }
    }
    text: {
        switch (library.status) {
        case "loading": return "Looking for your music…";
        case "empty": return "Copy music to the device over USB - into Music, or any folder - and it shows up here once the device has found it.";
        case "denied": return "To list your songs, albums and artists, Music has to be allowed to read the music library.";
        default: return library.errorText;
        }
    }
    buttonText: library.status === "denied" ? "Allow" : (library.status === "error" ? "Try Again" : "")
    onButtonClicked: library.status === "denied" ? library.retryPermission() : library.load()
}
