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

import QtCore as Core
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.LuneOS 2.0

import Eos.Window 0.1
import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0

import MusicApp 1.0

import LuneOS.Components 1.0 as LC
import "components"
import "js/Library.js" as Library
import "js/Queue.js" as Queue
import "js/Streaming.js" as Streaming

/*
 * Music: the songs on the device - by album, artist, genre, folder and
 * playlist - played from a queue, with Now Playing, a dashboard while the
 * card is away, and an exhibition view for the dock.
 *
 * The window holds what lives as long as the app does: the player, the
 * library, play counts and playlists. Pages are pushed on the stack and
 * reach all of it as "appWindow".
 */
WebOSWindow {
    id: appWindow

    readonly property string appId: "org.webosports.app.music"

    width: Settings.displayWidth
    height: Settings.displayHeight
    visible: true
    windowType: "_WEBOS_WINDOW_TYPE_CARD"
    title: "Music"
    color: theme.background

    // Closing the card while music plays must not stop it: the app stays
    // alive, with its dashboard, until the music is paused.
    keepAlive: player.playing

    // Where to look for music and where playlists are exported to.
    property string internalStorage: "/media/internal"
    property string mediaRoot: "/media"
    property string playlistDir: internalStorage + "/Playlists"
    // App data: the tag cache and the saved queue.
    property string dataDir: String(Core.StandardPaths.writableLocation(Core.StandardPaths.GenericDataLocation))
                             .replace(/^file:\/\//, "") + "/" + appId

    // A window as wide as a tablet's: the categories in a rail on the left.
    readonly property bool wide: width >= Units.gu(90)
    // A short window - the Q25's square, a phone turned sideways: slimmer
    // bars, and the views' sort and shuffle in a "..." at the end of the
    // tabs, so the music keeps most of the room.
    readonly property bool compact: height < Units.gu(50)
    readonly property bool nowPlayingOpen: nowPlayingLoader.item !== null && nowPlayingLoader.item.visible

    property alias theme: themeObject
    property alias prefs: preferences
    property alias player: player
    property alias library: library
    property alias stats: stats
    property alias playlists: playlists
    property alias streaming: streaming
    property alias lyricsLookup: lyricsLookup
    property alias artistLookup: artistLookup
    property alias artCache: artCache
    property alias sleepTimer: sleepTimer
    property alias sheet: sheet
    readonly property alias pageStack: stack

    // Streaming only while the streaming service runs and has a service
    // signed in.
    readonly property var categories: [
        { id: "albums", title: "Albums", icon: "album", view: "AlbumsView.qml" },
        { id: "artists", title: "Artists", icon: "artist", view: "ArtistsView.qml" },
        { id: "songs", title: "Songs", icon: "songs", view: "SongsView.qml" },
        { id: "genres", title: "Genres", icon: "genre", view: "GenresView.qml" },
        { id: "playlists", title: "Playlists", icon: "playlist", view: "PlaylistsView.qml" },
        { id: "folders", title: "Folders", icon: "folder", view: "FoldersView.qml" }
    ].concat(streaming.available ? [{ id: "streaming", title: "Streaming", icon: "stream", view: "StreamingView.qml" }] : [])

    Theme {
        id: themeObject
        followArt: preferences.followArt
        artAccent: accent.hasArt ? accent.color : "transparent"
    }

    ArtAccent {
        id: accent
        path: player.current ? player.current.path : ""
        album: player.current ? player.current.album : ""
    }

    PreferencesModel {
        id: preferences
    }

    ArtCache {
        id: artCache
    }

    LibraryStore {
        id: library
        clientName: appWindow.appId
        cacheDir: appWindow.dataDir
    }

    StatsStore {
        id: stats
        clientName: appWindow.appId
    }

    PlaylistStore {
        id: playlists
        clientName: appWindow.appId
        onFailed: function(text) { appWindow.notify(text); }
    }

    StreamingStore {
        id: streaming
        clientName: appWindow.appId
        preferredFormats: {
            try {
                return JSON.parse(preferences.streamFormats) || {};
            } catch (e) {
                return {};
            }
        }
    }

    LyricsLookup {
        id: lyricsLookup
        enabled: preferences.lyricsOnline
    }

    ArtistLookup {
        id: artistLookup
        enabled: preferences.artistOnline
    }

    PlaylistIO {
        id: playlistIO
        exportDir: appWindow.playlistDir
    }

    FileBrowser {
        id: files
    }

    StateFile {
        id: stateFile
        directory: appWindow.dataDir
    }

    Player {
        id: player
        rate: 1.0
        replayGain: preferences.replayGain
        preventClipping: preferences.preventClipping
        crossfadeMs: preferences.crossfade * 1000
        gainLookup: function(path) { return library.gainTags(path); }
        urlResolver: function(track, done, format) { streaming.resolve(track, done, format); }
        streamingTransport: streaming.transport
        resumeLookup: function(track) {
            return preferences.resumeLongTracks && Library.isLongForm(track) ? stats.bookmarkOf(track.path) : 0;
        }
        onFinished: function(track, playedMs, completed) {
            stats.trackFinished(track, playedMs, completed);
            appWindow.saveQueueSoon();
        }
        onBookmark: function(track, positionMs) {
            if (preferences.resumeLongTracks && Library.isLongForm(track))
                stats.setBookmark(track.path, positionMs);
        }
        onStarted: appWindow.saveQueueSoon()
        // One banner for a run of unplayable files (a format the device has
        // no decoder for fails every time), not one per file.
        onFailed: function(track, reason) {
            if (!appWindow.failureShown)
                appWindow.notify("Cannot play “" + track.title + "”: " + reason);
            appWindow.failureShown = true;
        }
        onQueueChanged: appWindow.saveQueueSoon()
        onPlayingChanged: {
            if (playing)
                appWindow.failureShown = false;
            appWindow.updateWakeActivity();
            if (!playing)
                appWindow.saveQueueSoon();
        }
    }

    SleepTimer {
        id: sleepTimer
        player: appWindow.player
        onExpired: appWindow.notify("Sleep timer: the music has stopped.")
    }

    // --- the saved queue -----------------------------------------------------

    function saveQueueSoon() {
        if (queueRestored)
            saveQueueTimer.restart();
    }

    function saveQueue() {
        saveQueueTimer.stop();
        if (queueRestored)
            stateFile.save("queue", Queue.serialize(player.queue, player.position));
    }

    property bool queueRestored: false
    property bool failureShown: false

    function restoreQueue() {
        var text = stateFile.load("queue");
        var state = text !== "" ? Queue.deserialize(text) : null;
        if (state)
            player.restore(state);
        queueRestored = true;
    }

    Timer {
        id: saveQueueTimer
        interval: 3000
        onTriggered: appWindow.saveQueue()
    }

    // Where the playing track is, now and then, so a crash or a reboot
    // loses at most half a minute.
    Timer {
        interval: 30000
        repeat: true
        running: player.playing
        onTriggered: appWindow.saveQueue()
    }

    Component.onCompleted: {
        restoreQueue();
        library.load();
        stats.load();
        playlists.load();
        streaming.refresh();
    }

    Component.onDestruction: {
        saveQueue();
        stats.flush();
        // Spotify plays in librespot, not in this process: ask it to stop
        // (best effort, the app is going).
        player.pause();
    }

    // --- the bus: staying awake, the clock -----------------------------------

    LunaService {
        id: service
        name: appWindow.appId
    }

    /*
     * Keeps the device from suspending while music plays: sleepd ends an
     * activity after at most 15 minutes, so it is renewed well before.
     * Needs "sleep.operation".
     */
    readonly property string wakeActivityId: appId + ".playback"

    function updateWakeActivity() {
        if (player.playing) {
            renewWakeActivity();
        } else {
            service.call("luna://com.palm.sleep/com/palm/power/activityEnd",
                         JSON.stringify({ "id": wakeActivityId }), function() {}, function() {});
        }
    }

    function renewWakeActivity() {
        service.call("luna://com.palm.sleep/com/palm/power/activityStart",
                     JSON.stringify({ "id": wakeActivityId, "duration_ms": 900000 }),
                     function() {},
                     function(error) { console.warn("Music: cannot keep the device awake: " + error); });
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: player.playing
        onTriggered: appWindow.renewWakeActivity()
    }

    // The clock style of Settings > Date & Time, for exhibition's clock.
    readonly property bool use24h: systemPrefs.values.timeFormat !== "HH12"

    SystemPreferences {
        id: systemPrefs
        keys: ["timeFormat"]
        clientName: appWindow.appId
    }

    // --- phone calls --------------------------------------------------------

    property bool pausedForCall: false

    // QOfono may be missing (a tablet without a modem): loaded, not imported.
    Loader {
        id: callWatcher
        source: Qt.resolvedUrl("CallWatcher.qml")
        asynchronous: true
    }
    Connections {
        target: callWatcher.item
        ignoreUnknownSignals: true
        function onCallStarted() {
            if (preferences.pauseOnCall && player.playing) {
                player.pause();
                appWindow.pausedForCall = true;
            }
        }
        function onCallsEnded() {
            if (appWindow.pausedForCall && preferences.resumeAfterCall)
                player.play();
            appWindow.pausedForCall = false;
        }
    }

    // --- the headset's buttons ----------------------------------------------------

    /* A media session of com.webos.service.mediacontroller: a Bluetooth
     * headset's buttons reach the player in the background too, not only
     * as media keys to the window in front (handleKey). */
    MediaSession {
        bus: service
        appId: appWindow.appId
        player: appWindow.player
    }

    // --- launch parameters ------------------------------------------------------

    /* The status bar's app menu relaunches the app with "palm-command":
     * "open-app-menu"; LaunchParams turns that into appMenuRequested.
     *
     * {"target": "<path or file:// URL>"} plays that file (Files opens audio
     * this way; a streamed track's "<provider>:<id>" plays from its service,
     * with "title", "artist" and "artUrl" if given)
     * or opens a playlist file; {"dockMode": true} - exhibition -
     * opens the exhibition window; {"action": "play" | "pause" | "toggle" |
     * "next" | "previous" | "shuffleAll"} drives the player, for a launcher
     * shortcut, Just Type or a test over the bus; {"category": "albums" |
     * "artists" | ...} and {"page": "nowPlaying" | "queue" | "search" |
     * "preferences" | "library"} open that part of the app; {"search": "<text>"}
     * (Just Type's Search Music action) searches the library for it. */
    LaunchParams {
        window: appWindow
        onAppMenuRequested: appMenu.popup(0, 0)
        onLaunched: function(params) {
            if (params.dockMode === true || params.windowType === "dockModeWindow")
                appWindow.exhibitionWanted = true;
            if (typeof params.target === "string" && params.target !== "")
                appWindow.openTarget(params.target, params);
            // Just Type's "Search Music": the search with what was typed.
            if (typeof params.search === "string") {
                appWindow.openSearch();
                stack.currentItem.text = params.search;
            }
            if (typeof params.category === "string" && appWindow.categories.some(function(c) { return c.id === params.category; })) {
                stack.pop(null);
                stack.currentItem.category = params.category;
            }
            switch (params.page) {
            case "nowPlaying":
                // Asked for together with a Shuffle All that waits for the
                // library: shown once there is something playing.
                if (!player.hasQueue)
                    appWindow.nowPlayingWanted = true;
                appWindow.openNowPlaying();
                break;
            case "queue": appWindow.openQueue(); break;
            case "search": appWindow.openSearch(); break;
            case "preferences": appWindow.openPreferences(); break;
            case "library": appWindow.closeNowPlaying(); stack.pop(null); break;
            }
            appWindow.runAction(params.action);
        }
    }

    // A launch action that needs the library ("shuffleAll" at a cold start)
    // waits for it to load.
    property string pendingAction: ""
    property bool nowPlayingWanted: false

    Connections {
        target: player
        function onHasQueueChanged() {
            if (player.hasQueue && appWindow.nowPlayingWanted) {
                appWindow.nowPlayingWanted = false;
                appWindow.openNowPlaying();
            }
        }
    }

    Connections {
        target: library
        function onStatusChanged() {
            if (library.status !== "loading" && appWindow.pendingAction !== "") {
                var action = appWindow.pendingAction;
                appWindow.pendingAction = "";
                appWindow.runAction(action);
            }
        }
    }

    function runAction(action) {
        if (action === "shuffleAll" && library.status === "loading") {
            pendingAction = action;
            return;
        }
        switch (action) {
        case "play": player.play(); break;
        case "pause": player.pause(); break;
        case "toggle": player.toggle(); break;
        case "next": player.next(); break;
        case "previous": player.previous(); break;
        case "shuffleAll": appWindow.shuffleAll(); break;
        }
    }

    function openTarget(target, params) {
        // A streamed track ("youtube:<id>", "tidal:<id>"...): played as it
        // is, with whatever title the launch carried.
        if (Streaming.isRemote(target) && !/^file:/.test(target)) {
            var s = Streaming.split(target);
            params = params || {};
            player.playTracks([{ path: String(target), title: params.title || String(target),
                                 artist: params.artist || streaming.providerName(s.provider),
                                 album: streaming.providerName(s.provider), duration: 0,
                                 artUrl: params.artUrl || "", provider: s.provider, remote: true }], 0, false);
            openNowPlaying();
            return;
        }
        var path = String(target).replace(/^file:\/\//, "");
        try {
            path = decodeURIComponent(path);
        } catch (e) {
            // Not percent-encoded after all.
        }
        if (playlistIO.isPlaylistFile(path)) {
            openPlaylistFile(path);
            return;
        }
        if (!files.exists(path)) {
            notify("Cannot find " + Library.fileName(path) + ".");
            return;
        }
        // The file and the music around it, starting with it.
        var siblings = files.list(files.folderOf(path)).filter(function(e) { return !e.isDir && !e.isPlaylist; })
                                                       .map(function(e) { return e.path; });
        if (siblings.indexOf(path) < 0)
            siblings = [path];
        player.playTracks(library.tracksFor(siblings), siblings.indexOf(path), false);
        openNowPlaying();
    }

    // --- exhibition ----------------------------------------------------------------

    property bool exhibitionWanted: false

    Loader {
        id: exhibitionLoader
        active: appWindow.exhibitionWanted
        sourceComponent: ExhibitionWindow {
            player: appWindow.player
            theme: themeObject
            use24h: appWindow.use24h
            onShuffleAllRequested: appWindow.shuffleAll()
            // The shell closes the window on undocking.
            onVisibleChanged: if (!visible) appWindow.exhibitionWanted = false
        }
    }

    // --- dashboard -------------------------------------------------------------------

    // The card in front - the card window, not the application: touching or
    // swiping the dashboard makes the application active too (its window takes
    // the focus), and taking that for the card dropped the dashboard before the
    // shell's close could reach it, the music playing on.
    readonly property bool cardActive: appWindow.active
    // Back in front: an account may have been added or removed meanwhile.
    onCardActiveChanged: if (cardActive) streaming.refresh()

    Loader {
        id: dashboardLoader
        active: !!(player.hasQueue && player.playing && !appWindow.cardActive && !appWindow.exhibitionWanted)
        sourceComponent: Dashboard {
            player: appWindow.player
            theme: themeObject
            onOpenRequested: appWindow.raise()
            // Only the user's swipe pauses; the Loader letting it go (the
            // card back in front) hides it too.
            onDismissed: if (dashboardLoader.active) appWindow.player.pause()
        }
    }

    // The library's light grey, as every LuneOS app has it (the window's
    // own colour is not drawn under a grab, nor on every compositor).
    Rectangle {
        anchors.fill: parent
        z: -1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.pageGradientTop }
            GradientStop { position: 1.0; color: Qt.lighter(Colors.pageGradientBottom, 1.35) }
        }
    }

    // --- layout ----------------------------------------------------------------------------

    MusicHeader {
        id: header
        anchors.top: parent.top
        width: parent.width
        theme: themeObject
        height: appWindow.compact ? Units.gu(6) : ((appWindow.height < Units.gu(70) || appWindow.width < Units.gu(50)) ? Units.gu(7.5) : Units.gu(9))
        title: stack.currentItem && stack.currentItem.title ? stack.currentItem.title : "Music"
        onSearchClicked: appWindow.openSearch()
    }

    // Under the header: something that went wrong, until dismissed.
    Item {
        id: noticeArea
        anchors.top: header.bottom
        width: parent.width
        height: statusNotice.visible ? statusNotice.height + Units.gu(2) : 0
        z: 5

        StatusNotice {
            id: statusNotice
            objectName: "statusNotice"
            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            visible: text !== ""
            text: appWindow.notice
            onDismissed: appWindow.notice = ""
        }
    }

    NavRail {
        id: rail
        anchors.top: noticeArea.bottom
        anchors.bottom: mini.top
        anchors.left: parent.left
        width: appWindow.wide ? Units.gu(22) : 0
        visible: appWindow.wide
        theme: themeObject
        categories: appWindow.categories
        current: stack.depth > 0 && stack.get(0) ? stack.get(0).category : ""
        playingTrack: player.current
        onCategoryClicked: function(id) {
            stack.pop(null);
            if (stack.currentItem)
                stack.currentItem.category = id;
        }
        onNowPlayingClicked: appWindow.openNowPlaying()
    }

    StackView {
        id: stack
        objectName: "pageStack"
        anchors.top: noticeArea.bottom
        anchors.bottom: mini.top
        anchors.left: rail.right
        anchors.right: parent.right
        clip: true
        focus: !appWindow.nowPlayingOpen && !sheet.shown
        initialItem: Qt.resolvedUrl("pages/LibraryPage.qml").toString()

        // The back gesture arrives as Escape (see LunaNext.Common's EventType).
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape && appWindow.goBack())
                event.accepted = true;
        }
        Keys.onPressed: function(event) {
            if (appWindow.handleKey(event))
                event.accepted = true;
        }
    }

    MiniPlayer {
        id: mini
        objectName: "miniPlayer"
        anchors.bottom: parent.bottom
        width: parent.width
        height: player.hasQueue ? (appWindow.compact ? Units.gu(6) : Units.gu(7.5)) : 0
        visible: player.hasQueue
        player: appWindow.player
        theme: themeObject
        onOpenRequested: appWindow.openNowPlaying()
    }

    // Now Playing slides up over everything.
    Loader {
        id: nowPlayingLoader
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height
        y: item && item.visible ? 0 : parent.height
        active: false
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        sourceComponent: NowPlaying {
            objectName: "nowPlaying"
            focus: visible
            player: appWindow.player
            theme: themeObject
            stats: appWindow.stats
            sleepTimer: appWindow.sleepTimer
            onCloseRequested: appWindow.closeNowPlaying()
            // Space and the media keys, not type-to-search, over the player.
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Space || (event.text || "").length !== 1)
                    event.accepted = appWindow.handleKey(event);
            }
            Keys.onReleased: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (showLyrics)
                        showLyrics = false;
                    else if (showArtist)
                        showArtist = false;
                    else
                        appWindow.closeNowPlaying();
                    event.accepted = true;
                }
            }
        }
    }

    LC.ActionSheet {
        id: sheet
        objectName: "actionSheet"
        anchors.fill: parent
    }

    LC.PromptDialog {
        id: prompt
        anchors.fill: parent
        visible: false
        z: 1001
        property var onDone: null
        onAccepted: function(text) {
            close();
            if (onDone)
                onDone(text);
        }
        onRejected: close()
    }

    LC.ConfirmDialog {
        id: confirm
        anchors.fill: parent
        visible: false
        z: 1001
        property var onDone: null
        onAccepted: {
            close();
            if (onDone)
                onDone();
        }
        onRejected: close()
    }


    property alias appMenu: appMenu

    Menu {
        id: appMenu
        // The app menu drops from the top of the window, as in every app.
        parent: appWindow.contentItem
        LuneOSMenu.appMenuStyle: true

        MenuItem {
            text: "Now Playing"
            enabled: player.hasQueue
            onTriggered: appWindow.openNowPlaying()
        }
        MenuItem {
            text: "Up Next"
            onTriggered: appWindow.openQueue()
        }
        MenuItem {
            text: "Sleep Timer"
            onTriggered: appWindow.chooseSleepTimer()
        }
        MenuItem {
            text: "Preferences"
            onTriggered: appWindow.openPreferences()
        }
    }

    // --- navigation ----------------------------------------------------------------------

    /* One step back: a sheet, Now Playing, a folder, a page. False when
     * there is nothing to go back from. */
    function goBack() {
        if (sheet.back())
            return true;
        if (nowPlayingOpen) {
            closeNowPlaying();
            return true;
        }
        if (stack.depth > 1) {
            stack.pop();
            return true;
        }
        var page = stack.currentItem;
        if (page && page.currentView && page.currentView.back)
            return page.currentView.back();
        return false;
    }

    function openNowPlaying() {
        if (!player.hasQueue)
            return;
        nowPlayingLoader.active = true;
        nowPlayingLoader.item.visible = true;
        nowPlayingLoader.item.forceActiveFocus();
    }

    function closeNowPlaying() {
        if (nowPlayingLoader.item)
            nowPlayingLoader.item.visible = false;
        stack.forceActiveFocus();
    }

    function push(url, properties) {
        closeNowPlaying();
        sheet.hide();
        return stack.push(Qt.resolvedUrl(url).toString(), properties || {});
    }

    function openAlbum(album) {
        if (!album)
            return;
        var page = push("pages/TrackListPage.qml", {
            title: album.title,
            subtitle: album.artist,
            detail: [album.year > 0 ? album.year : "", album.genre !== Library.unknownGenre ? album.genre : "",
                     Library.summary(album.tracks)].filter(function(x) { return x !== ""; }).join(" · "),
            songs: album.tracks,
            albumMode: true,
            artPath: album.artPath,
            artAlbum: album.title
        });
        page.objectName = "albumPage";
    }

    function openAlbumOf(track) {
        if (!track)
            return;
        var song = library.song(track.path);
        var album = song && song.albumKey ? library.album(song.albumKey) : null;
        if (album)
            openAlbum(album);
    }

    function openArtist(artist) {
        if (!artist)
            return;
        var page = push("pages/TrackListPage.qml", {
            title: artist.name,
            songs: artist.songs,
            albums: artist.albums,
            icon: "artist",
            roundCover: true,
            artPath: artist.artPath,
            artAlbum: artist.artAlbum
        });
        page.objectName = "artistPage";
    }

    function openArtistOf(track) {
        if (!track)
            return;
        var artist = library.artist(track.artist) || library.artist(track.albumArtist || "");
        if (artist)
            openArtist(artist);
    }

    function openGenre(genre) {
        if (!genre)
            return;
        var page = push("pages/TrackListPage.qml", {
            title: genre.name,
            songs: genre.songs,
            albums: genre.albums,
            icon: "genre",
            artPath: genre.artPath,
            artAlbum: genre.artAlbum
        });
        page.objectName = "genrePage";
    }

    function smartTracks(id) {
        return Library.smartPlaylist(id, library.lib.songs, stats.asMap(), Date.now(), 100);
    }

    function openSmartPlaylist(id) {
        var info = Library.smartPlaylists.filter(function(s) { return s.id === id; })[0];
        var page = push("pages/TrackListPage.qml", {
            title: info ? info.name : id,
            songs: smartTracks(id),
            icon: id === "favorites" ? "heart" : "playlist"
        });
        page.objectName = "smartPlaylistPage";
    }

    function openPlaylist(id) {
        var p = playlists.byId(id);
        if (!p)
            return;
        var page = push("pages/TrackListPage.qml", {
            title: p.name,
            songs: library.tracksFor(p.tracks),
            icon: "playlist",
            playlistId: id
        });
        page.objectName = "playlistPage";
        // The page follows the playlist as it is edited.
        var refresh = function() {
            var q = playlists.byId(id);
            if (!q)
                return;
            page.title = q.name;
            page.songs = library.tracksFor(q.tracks);
        };
        playlists.revisionChanged.connect(page, refresh);
        page.moveRequested.connect(function(from, to) { playlists.move(id, from, to); });
        page.removeRequested.connect(function(index) { playlists.removeAt(id, index); });
        page.actions = [];
    }

    // A playlist of the user's on a streaming service: as it is there, read
    // only, its tracks fetched when it is opened.
    function openServicePlaylist(providerId, playlist) {
        var page = push("pages/TrackListPage.qml", {
            title: playlist.name,
            subtitle: streaming.providerName(providerId),
            songs: [],
            icon: "playlist"
        });
        page.objectName = "servicePlaylistPage";
        page.loading = true;
        streaming.playlistTracks(providerId, playlist.id, function(tracks, error) {
            page.loading = false;
            page.songs = tracks;
            if (error)
                notify(error);
        });
    }

    function openPlaylistFile(path) {
        var paths = playlistIO.read(path);
        var page = push("pages/TrackListPage.qml", {
            title: Library.baseName(path),
            songs: library.tracksFor(paths),
            icon: "playlist"
        });
        page.objectName = "playlistFilePage";
    }

    function openStreamingService(id, text) {
        var page = push("pages/StreamSearchPage.qml", { providerId: id });
        page.objectName = "streamSearchPage";
        if (text)
            page.text = text;
    }

    function openQueue() {
        push("pages/QueuePage.qml");
    }

    function openSearch() {
        if (stack.currentItem && stack.currentItem.objectName === "searchPage")
            return;
        var page = push("pages/SearchPage.qml");
        page.objectName = "searchPage";
    }

    function openPreferences() {
        if (stack.currentItem && stack.currentItem.objectName === "preferencesPage")
            return;
        push("pages/PreferencesPage.qml");
    }

    function openSongInfo(song) {
        push("pages/SongInfoPage.qml", { song: song });
    }

    /*
     * A hardware keyboard (the Q25, a Key2, a TouchPad's): Space plays and
     * pauses, the media keys do what they say, and typing a letter anywhere
     * in the library starts a search with it - as Music Player Remix did.
     */
    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_MediaPlay:
        case Qt.Key_MediaTogglePlayPause:
            player.toggle();
            return true;
        case Qt.Key_MediaPause:
        case Qt.Key_MediaStop:
            player.pause();
            return true;
        case Qt.Key_MediaNext:
            player.next();
            return true;
        case Qt.Key_MediaPrevious:
            player.previous();
            return true;
        case Qt.Key_Space:
            if (stack.currentItem && stack.currentItem.objectName === "searchPage")
                return false;
            player.toggle();
            return true;
        }
        var text = event.text || "";
        if (text.length === 1 && /[\w\u00c0-\uffff]/.test(text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
                && !(stack.currentItem && stack.currentItem.objectName === "searchPage")) {
            openSearch();
            stack.currentItem.text = text;
            return true;
        }
        return false;
    }

    // --- actions -------------------------------------------------------------------------------

    /*
     * Tells the user something they only need to know: a banner, as the
     * guidelines have it (com.webos.notification's toast, which needs
     * "notification.operation"). Where there is no notification service -
     * the desktop tests - it goes in the notice under the header instead.
     */
    property string notice: ""
    property string lastNotification: ""

    function notify(text) {
        lastNotification = text;
        service.call("luna://com.webos.notification/createToast",
                     JSON.stringify({ sourceId: appId, message: text,
                                      iconUrl: Qt.resolvedUrl("../icon.png").toString().replace(/^file:\/\//, ""),
                                      // A banner only: the shell keeps an entry in
                                      // the notification area for every toast
                                      // that is not "light".
                                      noaction: true, onlyToast: true, type: "light" }),
                     function(message) {
                         var r = JSON.parse(message.payload);
                         if (r.returnValue === false)
                             appWindow.notice = text;
                     },
                     function() { appWindow.notice = text; });
    }

    function shuffleAll() {
        if (library.lib.songs.length === 0) {
            notify("There is no music to play yet.");
            return;
        }
        player.playTracks(library.lib.songs, -1, true);
    }

    function _enqueueChoices(tracks) {
        return [
            { label: "Play", action: function() { player.playTracks(tracks, 0, false); } },
            { label: "Shuffle", action: function() { player.playTracks(tracks, -1, true); } },
            { label: "Play Next", action: function() {
                player.playNext(tracks);
                appWindow.notify(tracks.length === 1 ? "Plays next." : Library.plural(tracks.length, "song", "songs") + " play next.");
            } },
            { label: "Add to Queue", action: function() {
                player.enqueue(tracks);
                appWindow.notify(Library.plural(tracks.length, "song", "songs") + " added to the queue.");
            } },
            { label: "Add to Playlist…", action: function() { appWindow.addToPlaylist(tracks.map(Streaming.stored)); } }
        ];
    }

    /* What can be done with a song. context: { playlistId, index } in a
     * playlist, { queueIndex } in the queue, { nowPlaying: true }. */
    function songMenu(song, context) {
        if (!song)
            return;
        context = context || {};
        var choices = [];
        if (!context.nowPlaying && context.queueIndex === undefined) {
            choices.push({ label: "Play Next", action: function() { player.playNext([song]); appWindow.notify("Plays next."); } });
            choices.push({ label: "Add to Queue", action: function() { player.enqueue([song]); appWindow.notify("Added to the queue."); } });
        }
        if (context.queueIndex !== undefined)
            choices.push({ label: "Remove from Up Next", action: function() { player.removeItem(context.queueIndex); } });
        choices.push({ label: "Add to Playlist…", action: function() { appWindow.addToPlaylist([Streaming.stored(song)]); } });
        var fav = stats.isFavorite(song.path);
        choices.push({ label: fav ? "Remove from Favorites" : "Add to Favorites",
                       action: function() { stats.setFavorite(song.path, !fav); } });
        if (library.song(song.path)) {
            choices.push({ label: "Go to Album", action: function() { appWindow.openAlbumOf(song); } });
            choices.push({ label: "Go to Artist", action: function() { appWindow.openArtistOf(song); } });
        }
        // A streamed track has no file to read tags from.
        if (!song.remote)
            choices.push({ label: "Song Info", action: function() { appWindow.openSongInfo(song); } });
        if (context.playlistId)
            choices.push({ label: "Remove from Playlist", destructive: true,
                           action: function() { playlists.removeAt(context.playlistId, context.index); } });
        sheet.show(song.title, choices, song.remote ? song.artist + " · " + streaming.providerName(song.provider)
                                                    : song.artist + " — " + song.album);
    }

    function albumMenu(album) {
        if (!album)
            return;
        var choices = _enqueueChoices(album.tracks);
        choices.push({ label: "Go to Artist", action: function() { appWindow.openArtist(library.artist(album.artist)); } });
        sheet.show(album.title, choices, album.artist);
    }

    function collectionMenu(name, tracks) {
        sheet.show(name, _enqueueChoices(tracks), Library.summary(tracks));
    }

    function folderMenu(path, folderView) {
        var tracks = function() { return library.tracksFor(files.audioFilesUnder(path, 5000)); };
        sheet.show(Library.fileName(path), [
            { label: "Play Folder", action: function() { folderView.playFolder(path, false); } },
            { label: "Shuffle Folder", action: function() { folderView.playFolder(path, true); } },
            { label: "Play Next", action: function() { player.playNext(tracks()); } },
            { label: "Add to Queue", action: function() { player.enqueue(tracks()); } }
        ], path);
    }

    function playlistFileMenu(path) {
        sheet.show(Library.baseName(path), [
            { label: "Play", action: function() { player.playTracks(library.tracksFor(playlistIO.read(path)), 0, false); } },
            { label: "Import as Playlist", action: function() {
                var paths = playlistIO.read(path);
                playlists.create(Library.baseName(path), paths, function(p) {
                    appWindow.notify("Imported “" + p.name + "” with " + Library.plural(paths.length, "song", "songs") + ".");
                });
            } }
        ], "Playlist file");
    }

    function playlistMenu(id) {
        var p = playlists.byId(id);
        if (!p)
            return;
        var tracks = library.tracksFor(p.tracks);
        var choices = _enqueueChoices(tracks).slice(0, 4);
        choices.push({ label: "Rename…", action: function() {
            prompt.title = "Rename Playlist";
            prompt.defaultValue = p.name;
            prompt.onDone = function(text) { playlists.rename(id, text); };
            prompt.open();
        } });
        choices.push({ label: "Export to " + Library.fileName(playlistDir), action: function() {
            // Streamed tracks mean nothing to another player: files only.
            var file = playlistIO.write(p.name, tracks.filter(function(t) { return !t.remote; }));
            appWindow.notify(file !== "" ? "Saved as " + file : "The playlist could not be saved.");
        } });
        choices.push({ label: "Delete", destructive: true, action: function() {
            confirm.title = "Delete “" + p.name + "”?";
            confirm.message = "The songs stay in your library.";
            confirm.acceptText = "Delete";
            confirm.destructive = true;
            confirm.onDone = function() {
                if (stack.currentItem && stack.currentItem.playlistId === id)
                    stack.pop();
                playlists.remove(id);
            };
            confirm.open();
        } });
        sheet.show(p.name, choices, Library.plural(p.tracks.length, "song", "songs"));
    }

    function newPlaylist(paths) {
        prompt.title = "New Playlist";
        prompt.defaultValue = playlists.uniqueName("Playlist");
        prompt.onDone = function(text) {
            playlists.create(text, paths, function(p) {
                appWindow.notify(paths.length > 0 ? "Saved “" + p.name + "”." : "Made “" + p.name + "”.");
            });
        };
        prompt.open();
    }

    function addToPlaylist(paths) {
        var choices = [{ label: "New Playlist…", action: function() { appWindow.newPlaylist(paths); } }];
        playlists.playlists.forEach(function(p) {
            choices.push({ label: p.name, action: function() {
                playlists.add(p._id, paths);
                appWindow.notify(Library.plural(paths.length, "song", "songs") + " added to “" + p.name + "”.");
            } });
        });
        sheet.show("Add to Playlist", choices, Library.plural(paths.length, "song", "songs"));
    }

    function chooseSort(title, options, current, apply) {
        sheet.show(title, options.map(function(o) {
            return { label: o.text, checked: o.key === current, action: function() { apply(o.key); } };
        }), "");
    }

    function chooseSleepTimer() {
        var choices = [15, 30, 45, 60, 90].map(function(m) {
            return { label: m + " Minutes", action: function() {
                sleepTimer.start(m);
                appWindow.notify("The music stops in " + m + " minutes.");
            } };
        });
        choices.push({ label: "End of This Song", checked: sleepTimer.endOfTrack, enabled: player.hasQueue,
                       action: function() { sleepTimer.stopAtEndOfTrack(); } });
        if (sleepTimer.running)
            choices.push({ label: "Turn Off", destructive: true, action: function() { sleepTimer.cancel(); } });
        sheet.show("Sleep Timer", choices, sleepTimer.running ? "Stops in " + sleepTimer.remainingText : "");
    }

    // The streamed track's formats, when its service offers more than one;
    // the one picked is kept for that service's next tracks.
    function chooseFormat() {
        var f = player.currentFormat;
        var parts = player.current ? Streaming.split(player.current.path) : null;
        if (!f || f.formats.length < 2 || !parts)
            return;
        sheet.show("Quality", f.formats.map(function(label) {
            return { label: label, checked: label === f.format, action: function() {
                var picked = Object.assign({}, streaming.preferredFormats);
                picked[parts.provider] = label;
                preferences.streamFormats = JSON.stringify(picked);
                player.switchFormat(label, function(error) {
                    if (error)
                        appWindow.notify(error);
                });
            } };
        }), streaming.providerName(parts.provider));
    }

    function chooseSpeed() {
        sheet.show("Speed", [0.5, 0.75, 1, 1.25, 1.5, 2].map(function(r) {
            return { label: r === 1 ? "Normal" : r + "×", checked: player.rate === r,
                     action: function() { player.rate = r; } };
        }), "");
    }
}
