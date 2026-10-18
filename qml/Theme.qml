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
import LuneOS.Forms 1.0

/*
 * The app's two looks, as the legacy Music app had them and the webOS
 * guidelines describe: the library light, in the colours of every LuneOS
 * app (LuneOS.Forms' Colors), and the player dark ("palm-dark") - Now
 * Playing, the mini player, the dashboard and exhibition - so the cover
 * carries the colour. The accent follows the playing track's cover when
 * the user leaves that on.
 */
QtObject {
    id: theme

    // The cover's colour (ArtAccent), when there is one to follow.
    property color artAccent: "transparent"
    property bool followArt: true

    readonly property color baseAccent: "#3a87c8"
    // For the dark player: ArtAccent keeps it light enough for that.
    readonly property color accent: followArt && artAccent.a > 0 ? artAccent : baseAccent
    // The same colour, deep enough to read on the light library.
    readonly property color accentOnLight: followArt && artAccent.a > 0 ? Qt.darker(artAccent, 1.6) : "#2a6fb0"

    // --- the library (light) ----------------------------------------------
    readonly property color background: Colors.pageBackground
    readonly property color surface: "#e6e6e6"
    readonly property color pressed: "#26000000"
    readonly property color divider: Colors.ruleDark
    readonly property color dividerLight: Colors.ruleLight
    readonly property color text: Colors.text
    readonly property color secondaryText: Colors.secondaryText
    readonly property color faintText: "#8a8a8a"
    readonly property color error: Colors.error
    readonly property color coverPlaceholder: "#c4c4c4"

    // --- the player (dark) ------------------------------------------------
    readonly property color darkBackground: "#141414"
    readonly property color darkSurface: "#1f1f1f"
    readonly property color darkRaised: "#2a2a2a"
    readonly property color darkPressed: "#33ffffff"
    readonly property color darkDivider: "#2e2e2e"
    readonly property color darkText: "#f4f4f4"
    readonly property color darkSecondaryText: "#a6a6a6"
    readonly property color darkFaintText: "#6e6e6e"

    readonly property real fontLarge: FontUtils.sizeToPixels("large")
    readonly property real fontMedium: FontUtils.sizeToPixels("medium")
    readonly property real fontSmall: FontUtils.sizeToPixels("small")
    readonly property real fontTiny: FontUtils.sizeToPixels("x-small")

    // The legacy guidelines' smallest touch target is 54 px.
    readonly property real rowHeight: Math.max(Units.gu(7), 54)
    readonly property real margin: Units.gu(1.5)
}
