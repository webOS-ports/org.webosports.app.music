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

/*
 * A row that leads somewhere - an artist, a genre, a playlist, a folder:
 * a cover or an icon, a title and a line under it, and "…" when there is
 * more to do than open it. With swipeToDelete, swiped sideways past a third
 * of its width it asks Delete / Cancel in place, as the Sound Recorder's
 * rows do; short of that it springs back.
 */
Item {
    id: row

    property var theme
    property string title: ""
    property string subtitle: ""
    // A cover from this track, or else the icon.
    property string artPath: ""
    property string artAlbum: ""
    property string artUrl: ""
    property string icon: ""
    // An image to show as it is, on no tile (a service's own icon), in
    // place of a cover; the icon while it is not there.
    property string iconUrl: ""
    property bool round: false
    property bool showMenu: false
    property bool swipeToDelete: false
    // Swiped away and confirmed in the row: delete without asking again.
    signal swipeDeleted()

    signal clicked()
    signal menuRequested()

    // Asking Delete / Cancel.
    property bool confirming: false

    function cancelSwipe() {
        confirming = false;
        content.x = 0;
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    height: theme.rowHeight
    clip: content.x !== 0

    // Under the row while it is swiped: the question.
    Rectangle {
        anchors.fill: parent
        visible: content.x !== 0 || row.confirming
        color: "#5a5a5a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: row.theme.margin
            anchors.rightMargin: row.theme.margin
            spacing: row.theme.margin
            visible: row.confirming

            Item { Layout.fillWidth: true }
            Button {
                objectName: "swipeDeleteButton"
                text: "Delete"
                LuneOSButton.mainColor: LuneOSButton.negativeColor
                onClicked: { row.confirming = false; row.swipeDeleted(); }
            }
            Button {
                objectName: "swipeCancelButton"
                text: "Cancel"
                onClicked: row.cancelSwipe()
            }
            Item { Layout.fillWidth: true }
        }
    }

    Item {
        id: content
        objectName: "rowContent"
        width: parent.width
        height: parent.height
        visible: !row.confirming

        Behavior on x {
            enabled: !swipe.active
            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
        }

        Rectangle {
            anchors.fill: parent
            visible: content.x !== 0
            color: row.theme.background
        }

        Rectangle {
            anchors.fill: parent
            color: mouse.pressed ? row.theme.pressed : "transparent"
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            onClicked: row.clicked()
            onPressAndHold: if (row.showMenu) row.menuRequested()
        }

        Cover {
            id: lead
            anchors.left: parent.left
            anchors.leftMargin: row.theme.margin
            anchors.verticalCenter: parent.verticalCenter
            width: Units.gu(5)
            height: width
            radius: row.round ? width / 2 : Math.max(2, width / 40)
            path: row.artPath
            album: row.artAlbum
            artUrl: row.iconUrl !== "" ? row.iconUrl : row.artUrl
            color: row.iconUrl !== "" && hasArt ? "transparent" : (onLight ? "#c4c4c4" : "#2b2b2b")
            fillMode: row.iconUrl !== "" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            placeholderIcon: row.icon !== "" ? row.icon : "note"
        }

        Column {
            anchors.left: lead.right
            anchors.leftMargin: row.theme.margin
            anchors.right: menuButton.visible ? menuButton.left : parent.right
            anchors.rightMargin: row.theme.margin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Units.gu(0.2)

            Text {
                width: parent.width
                text: row.title
                color: row.theme.text
                font.pixelSize: row.theme.fontMedium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: row.subtitle
                color: row.theme.secondaryText
                font.pixelSize: row.theme.fontSmall
                elide: Text.ElideRight
                visible: text !== ""
            }
        }

        IconButton {
            id: menuButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: row.showMenu
            image: "more"
            label: "More"
            iconSize: Units.gu(2.4)
            accent: row.theme.accentOnLight
            onLight: true
            onClicked: row.menuRequested()
        }

        DragHandler {
            id: swipe
            enabled: row.swipeToDelete
            target: content
            yAxis.enabled: false
            xAxis.minimum: -row.width
            xAxis.maximum: row.width
            onActiveChanged: {
                if (active)
                    return;
                if (Math.abs(content.x) > row.width / 3)
                    row.confirming = true;
                content.x = 0;
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        // Under the text, past the cover.
        anchors.leftMargin: row.theme.margin * 2 + lead.width
        anchors.right: parent.right
        height: 1
        color: row.theme.divider
    }
}
