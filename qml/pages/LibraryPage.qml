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

/*
 * The library: Albums, Artists, Songs, Genres, Playlists and Folders. On a
 * phone a row of tabs picks one (swipe the content sideways to step
 * through them); on a tablet the rail at the window's left does, and the
 * tabs are not shown.
 */
Item {
    id: page

    property string title: "Music"
    readonly property var theme: appWindow.theme
    property string category: appWindow.prefs.lastCategory
    property bool showTabs: !appWindow.wide

    readonly property var categories: appWindow.categories
    readonly property int currentIndex: {
        for (var i = 0; i < categories.length; i++) {
            if (categories[i].id === category)
                return i;
        }
        return 0;
    }

    onCategoryChanged: appWindow.prefs.lastCategory = category

    // The view currently shown, for the back gesture (Folders steps out of
    // a folder before the app goes back).
    readonly property var currentView: views.itemAt(currentIndex) ? views.itemAt(currentIndex).item : null

    ListView {
        id: tabs
        objectName: "categoryTabs"
        height: page.showTabs ? (appWindow.compact ? Units.gu(4.5) : Units.gu(5.5)) : 0
        anchors.right: viewMenu.visible ? viewMenu.left : parent.right
        anchors.left: parent.left
        visible: page.showTabs
        orientation: ListView.Horizontal
        model: page.categories
        currentIndex: page.currentIndex
        highlightFollowsCurrentItem: true
        highlightMoveDuration: 150
        clip: true
        leftMargin: Units.gu(0.5)
        delegate: Item {
            required property var modelData
            required property int index
            width: label.implicitWidth + Units.gu(3)
            height: tabs.height
            Text {
                id: label
                anchors.centerIn: parent
                text: modelData.title
                color: index === page.currentIndex ? page.theme.text : page.theme.secondaryText
                font.pixelSize: page.theme.fontMedium
                font.weight: index === page.currentIndex ? Font.DemiBold : Font.Normal
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: label.implicitWidth
                height: Units.gu(0.35)
                radius: height / 2
                color: page.theme.accentOnLight
                visible: index === page.currentIndex
            }
            MouseArea {
                anchors.fill: parent
                onClicked: page.category = modelData.id
            }
        }
    }

    // A short window has no view bar: its sort and shuffle are here.
    IconButton {
        id: viewMenu
        objectName: "viewMenuButton"
        anchors.right: parent.right
        anchors.verticalCenter: tabs.verticalCenter
        visible: page.showTabs && appWindow.compact && !!page.currentView && page.currentView.viewActions !== undefined
        width: visible ? implicitWidth : 0
        image: "more"
        label: "Sort and shuffle"
        iconSize: Units.gu(2.4)
        onLight: true
        onClicked: appWindow.sheet.show(page.categories[page.currentIndex].title, page.currentView.viewActions)
    }

    Rectangle {
        anchors.top: tabs.bottom
        width: parent.width
        height: 1
        color: page.theme.divider
        visible: page.showTabs
    }

    Item {
        id: content
        anchors.top: tabs.bottom
        anchors.topMargin: page.showTabs ? 1 : 0
        anchors.bottom: parent.bottom
        width: parent.width

        Repeater {
            id: views
            model: page.categories
            delegate: Loader {
                required property var modelData
                required property int index
                anchors.fill: parent
                // Each view is made the first time it is shown and kept.
                active: index === page.currentIndex || item !== null
                visible: index === page.currentIndex
                source: Qt.resolvedUrl("../views/" + modelData.view)
            }
        }
    }
}
