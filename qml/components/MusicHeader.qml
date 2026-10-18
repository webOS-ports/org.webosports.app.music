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
import LuneOS.Forms 1.0 as Forms

/*
 * The light toolbar over the library - LuneOS.Forms' AppHeader, as every
 * LuneOS app has: the app's icon, the page's title and Search on the
 * right. No Back key: every LuneOS device has the back gesture.
 */
Forms.AppHeader {
    id: header

    property var theme
    property bool showSearch: true

    signal searchClicked()

    icon: Qt.resolvedUrl("../../icon.png")
    compact: width < Units.gu(50)

    actionComponent: Component {
        IconButton {
            objectName: "headerSearch"
            visible: header.showSearch
            image: "search"
            label: "Search"
            onLight: true
            onClicked: header.searchClicked()
        }
    }
}
