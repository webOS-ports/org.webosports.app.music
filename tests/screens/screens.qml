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
import LuneOS.Service 1.0

/*
 * Walks the app through its screens at the device profile's screen size
 * and grid unit (Settings/Units from the stand-ins), saving each to
 * <out>/<profile>-<screen>.png, then quits. Loaded by musicapp-screens.
 */
QtObject {
    id: run

    readonly property string fixtures: String(Qt.resolvedUrl("../fixtures/music")).replace(/^file:\/\//, "")
    property var app: null
    property int step: 0

    property LunaService bus: LunaService {
        name: "org.webosports.app.music.screens"
    }

    function records() {
        var f = fixtures;
        function r(rel, title, artist, album, track, disc, genre) {
            return { _kind: "com.palm.media.audio.file:1", path: f + "/" + rel, title: title, artist: artist,
                     albumArtist: artist, album: album, genre: genre, track: { position: track, total: 0 },
                     disc: { position: disc, total: 0 }, duration: 0, modifiedTime: 100 };
        }
        return [
            r("Ana Ray/Red Sky/01 Red Song 1.mp3", "Red Song 1", "Ana Ray", "Red Sky", 1, 0, "Pop"),
            r("Ana Ray/Red Sky/02 Red Song 2.mp3", "Red Song 2", "Ana Ray", "Red Sky", 2, 0, "Pop"),
            r("Ana Ray/Red Sky/03 Red Song 3.mp3", "Red Song 3", "Ana Ray", "Red Sky", 3, 0, "Pop"),
            r("Blue Band/Deep Water/CD1/01 Deep 1-1.flac", "Deep 1-1", "Blue Band", "Deep Water", 1, 1, "Rock"),
            r("Blue Band/Deep Water/CD1/02 Deep 1-2.flac", "Deep 1-2", "Blue Band", "Deep Water", 2, 1, "Rock"),
            r("Blue Band/Deep Water/CD2/01 Deep 2-1.flac", "Deep 2-1", "Blue Band", "Deep Water", 1, 2, "Rock"),
            r("Blue Band/Deep Water/CD2/02 Deep 2-2.flac", "Deep 2-2", "Blue Band", "Deep Water", 2, 2, "Rock"),
            r("Various/Summer Mix/01 Ana Ray - Sun.ogg", "Sun 1", "Ana Ray", "Summer Mix", 1, 0, "Dance"),
            r("Various/Summer Mix/02 Cool Cats - Sun.ogg", "Sun 2", "Cool Cats", "Summer Mix", 2, 0, "Dance"),
            r("Various/Summer Mix/03 Zed - Sun.ogg", "Sun 3", "Zed", "Summer Mix", 3, 0, "Dance")
        ];
    }

    function album(title) {
        return app.library.lib.albums.filter(function(a) { return a.title === title; })[0];
    }

    // Each step sets a screen up; the grab follows a moment later, once
    // covers have loaded and transitions have finished.
    readonly property var steps: [
        ["albums", function() { app.pageStack.get(0).category = "albums"; }],
        ["artists", function() { app.pageStack.get(0).category = "artists"; }],
        ["songs", function() { app.pageStack.get(0).category = "songs"; }],
        ["playlists", function() { app.pageStack.get(0).category = "playlists"; }],
        // The playlist dialogs, over the playlists
        ["playlist-new", function() { app.newPlaylist([]); }],
        ["playlist-rename", function() {
            dialogOf("promptRejectButton").reject();
            app.playlists.create("Road Mix", [], function(p) {
                run.playlistId = p._id;
                app.playlistMenu(p._id);
                chooseInSheet("Rename…");
            });
        }],
        ["playlist-delete", function() {
            dialogOf("promptRejectButton").reject();
            app.playlistMenu(run.playlistId);
            chooseInSheet("Delete");
        }],
        ["folders", function() { dialogOf("confirmRejectButton").rejected(); app.pageStack.get(0).category = "folders"; }],
        ["view-menu", function() {
            app.pageStack.get(0).category = "albums";
            if (app.compact)
                app.sheet.show("Albums", app.pageStack.get(0).currentView.viewActions);
        }],
        ["album", function() { app.sheet.hide(); app.openAlbum(album("Deep Water")); }],
        ["artist", function() { app.openArtist(app.library.artist("Ana Ray")); }],
        ["song-menu", function() { app.songMenu(album("Red Sky").tracks[0], null); }],
        ["queue", function() {
            app.sheet.hide();
            app.player.playTracks(album("Red Sky").tracks.concat(album("Deep Water").tracks), 0, false);
            app.player.pause();
            app.openQueue();
        }],
        ["now-playing", function() { app.openNowPlaying(); }],
        ["lyrics", function() { app.findChild ? null : null; nowPlaying().showLyrics = true; }],
        ["search", function() { nowPlaying().showLyrics = false; app.closeNowPlaying(); app.openSearch(); app.pageStack.currentItem.text = "sun"; }],
        ["preferences", function() { app.openPreferences(); }],
        ["exhibition", function() { app.pageStack.pop(null); app.exhibitionWanted = true; }]
    ]

    property string playlistId: ""

    function findNamed(name) {
        var items = [app.contentItem];
        while (items.length) {
            var it = items.shift();
            if (it.objectName === name)
                return it;
            for (var i = 0; i < it.children.length; i++)
                items.push(it.children[i]);
        }
        return null;
    }

    // The dialog (luneos-components' PromptDialog or ConfirmDialog) a
    // button is in
    function dialogOf(button) {
        var it = findNamed(button);
        while (it && it.acceptText === undefined)
            it = it.parent;
        return it;
    }

    function chooseInSheet(label) {
        var labels = app.sheet.choices.map(function(c) { return c.label; });
        app.sheet.choose(labels.indexOf(label));
    }

    function nowPlaying() {
        var items = [app.contentItem];
        while (items.length) {
            var it = items.shift();
            if (it.objectName === "nowPlaying")
                return it;
            for (var i = 0; i < it.children.length; i++)
                items.push(it.children[i]);
        }
        return null;
    }

    function grab(name) {
        var target = name === "exhibition" ? exhibitionContent() : app.contentItem;
        target.grabToImage(function(result) {
            result.saveToFile(screensOut + "/" + screensProfile + "-" + name + ".png");
            next.start();
        });
    }

    function exhibitionContent() {
        // The exhibition window is the Loader's item in main.qml.
        for (var i = 0; i < app.data.length; i++) {
            var d = app.data[i];
            if (d && d.item && d.item.windowType === "_WEBOS_WINDOW_TYPE_DOCK")
                return d.item.contentItem;
        }
        return app.contentItem;
    }

    property Timer settle: Timer {
        interval: 900
        onTriggered: run.grab(run.steps[run.step][0])
    }

    property Timer next: Timer {
        interval: 50
        onTriggered: {
            run.step++;
            if (run.step >= run.steps.length) {
                Qt.quit();
                return;
            }
            run.steps[run.step][1]();
            run.settle.start();
        }
    }

    property Timer waitForLibrary: Timer {
        interval: 200
        repeat: true
        onTriggered: {
            if (run.app.library.status === "ready" && !run.app.library.enriching) {
                stop();
                run.steps[0][1]();
                run.settle.start();
            }
        }
    }

    Component.onCompleted: {
        bus.call("luna://com.palm.db/put", JSON.stringify({ objects: records() }), function() {}, function() {});
        var c = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (c.status === Component.Error) {
            console.error(c.errorString());
            Qt.exit(2);
            return;
        }
        app = c.createObject(null, { width: Settings.displayWidth, height: Settings.displayHeight,
                                     internalStorage: fixtures });
        waitForLibrary.start();
    }
}
