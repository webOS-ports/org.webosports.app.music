# Music

The music player of LuneOS: the songs on the device by album, artist,
genre, folder and playlist, played from a queue, with Now Playing, a
dashboard while the card is away and an exhibition view for the dock.

A QML app (`"type": "qml"`, run by qml-runner) with a small C++ plugin for
what QML cannot do: reading tags and covers with TagLib, caching them, and
reading and writing playlist files.

## Screenshots

Taken on the devices with the demo library from
`tools/make-demo-library.sh` (made-up artists, generated covers).

Phone (MindPhone, 480x800):

| Albums | Album | Now Playing | Lyrics |
|---|---|---|---|
| ![](docs/screenshots/phone-albums.png) | ![](docs/screenshots/phone-album.png) | ![](docs/screenshots/phone-now-playing.png) | ![](docs/screenshots/phone-lyrics.png) |
| **Up Next** | **Song menu** | **Search** | **Exhibition** |
| ![](docs/screenshots/phone-queue.png) | ![](docs/screenshots/phone-song-menu.png) | ![](docs/screenshots/phone-search.png) | ![](docs/screenshots/phone-exhibition.png) |
| **Artists** | **Preferences** | **Song info** | |
| ![](docs/screenshots/phone-artists.png) | ![](docs/screenshots/phone-preferences.png) | ![](docs/screenshots/phone-song-info.png) | |

Q25 (720x720, with its keyboard the card is 720x545):

| Albums | Album | Now Playing |
|---|---|---|
| ![](docs/screenshots/q25-albums.png) | ![](docs/screenshots/q25-album.png) | ![](docs/screenshots/q25-now-playing.png) |
| **Up Next** | **Search** | |
| ![](docs/screenshots/q25-queue.png) | ![](docs/screenshots/q25-search.png) | |

Tablet (TouchPad, 1024x768):

| Albums | Album |
|---|---|
| ![](docs/screenshots/tablet-albums.png) | ![](docs/screenshots/tablet-album.png) |
| **Now Playing** | **Lyrics** |
| ![](docs/screenshots/tablet-now-playing.png) | ![](docs/screenshots/tablet-lyrics.png) |
| **Up Next** | **Search** |
| ![](docs/screenshots/tablet-queue.png) | ![](docs/screenshots/tablet-search.png) |

## What it does

**Library**
- From the media indexer (`com.palm.media.audio.file:1` in db8): Albums
  (grid of covers), Artists (album artists, plus everyone who appears on
  someone else's albums), Songs, Genres, Playlists and Folders.
- Albums are worked out by the app: a compilation without album artist
  tags is one album by Various Artists, a two-disc set in `CD1`/`CD2`
  folders is one album with disc headings.
- What the indexer leaves out - lengths, years, composers, ReplayGain, album
  artist tags - is read with TagLib in the background and kept in a cache.
- Covers from the files' tags (ID3 APIC, MP4 covr, FLAC/Vorbis pictures) or
  from `cover.jpg`/`folder.jpg`/`AlbumArt_*_Large.jpg` beside them (a disc
  folder looks one up), scaled once and cached.
- Sorting (title, artist, album, year, recently added, length), an A-Z fast
  scroller on long lists, search as you type, and the folder view for cards
  and sticks the indexer does not scan.
- Ringtones, alarms, notifications and hidden folders are left out, and so
  are songs whose file is gone though the indexer still lists them.

**Playback**
- Near-gapless (the next track is loaded in a second decoder before the
  current one ends) or crossfade of 2-12 s.
- Volume levelling from ReplayGain tags: off, track, album, or automatic
  (album gain while an album plays in order), with clipping prevention.
- Shuffle that keeps the playing track first and can be undone; repeat
  all / one; play next, add to queue, reorder, remove, save the queue as a
  playlist; the queue and position are kept across restarts.
- Audiobooks, podcasts and tracks over 20 minutes carry on where they were
  left. Sleep timer (minutes or end of track, fading out), playback speed.
- Pauses for phone calls and carries on after (QOfono).
- Keeps the device awake while playing; the card can be closed and the music
  plays on, with a dashboard to control it; swiping the dashboard away
  stops it (Spotify included, which plays outside the app).

**Streaming** (Synergy accounts)
- Spotify, Tidal, Deezer, Qobuz, Apple Music, SoundCloud, Jamendo and the
  Internet Archive, signed in as accounts in Accounts (Add Account), plus
  YouTube, which needs none - through the music streaming service
  (`luneos-synergy-music`, the spotify-webos-service daemon on
  127.0.0.1:8730) and its connectors.
- A Streaming category (shown while the service runs and a service is
  signed in) with a search per service, and a section per service under the
  library's results in Search.
- The daemon resolves a track to a URL (`/provider/<id>/resolve`) and the
  app plays it itself, so streams seek, take the volume, ReplayGain,
  crossfade and the sleep timer like files; Spotify plays through the
  daemon's librespot (Spotify Connect), driven by the app.
- Where a service has a track in more than one format (SoundCloud's AAC 160
  and 96, YouTube's AAC and Opus), Now Playing shows the one playing under
  the seek bar; a tap offers the others, switches where the track is, and
  keeps the choice for that service's next tracks.
- Streamed tracks queue, favourite and go into playlists like files (a
  playlist keeps their title and cover); the queue keeps them across
  restarts.

**Playlists and listening history**
- Playlists in the app's own db8 kind; import M3U/M3U8/PLS from Folders,
  export M3U8 to `/media/internal/Playlists`.
- Favourites, play counts and skips (Last.fm's rule: half the track or four
  minutes, tracks of at least 30 s), and the automatic lists: Favorites,
  Recently Added, Recently Played, Most Played, Never Played, Memory Lane.

**Now Playing**
- Large cover, blurred behind, the colour of the cover as the accent.
- Swipe the cover for the next/previous track; tap its left edge, middle or
  right edge for previous, play/pause, next (as Music Player Remix had it);
  hold Previous/Next to rewind or fast-forward, faster the longer.
- Synced lyrics (LRC, embedded or a `.lrc` beside the file) following the
  music, tap a line to go there; plain lyrics scroll.
- Songs without lyrics of their own - streamed ones, files without them -
  get them from LRCLIB (lrclib.net) by artist and title, credited; it can
  be switched off in Preferences.
- Song info (tags, format, gains, play counts).

**webOS**
- Exhibition (`"exhibitionMode": true`): the shell launches the app with
  `dockMode` and it opens a window of the dock type - clock, cover, track and
  large controls, or Shuffle All when nothing is queued.
- Dashboard (floating window) while the card is away and music plays.
- Banners through `com.webos.notification` for things worth knowing.
- The app menu (status bar): Now Playing, Up Next, Sleep Timer, Preferences.
- Back gesture everywhere (Escape), no Back keys.
- Hardware keyboards: Space, media keys, and typing starts a search.
- Opens audio files and playlists from Files (`mimeTypes`).
- Just Type (`universalSearch`): "Songs" finds the indexer's songs by
  artist, album or title and plays the one picked; "Search Music" opens the
  app's search with what was typed.
- The look of the other LuneOS apps (LuneOS.Forms: light library, AppHeader,
  StatusNotice) with a dark player, as the legacy Music app and the webOS
  guidelines have it; laid out for phones, the Q25's square and tablets
  (a rail of categories), with slimmer bars on a short window.

**Launch parameters**, for launcher shortcuts and tests:
`{"action": "play" | "pause" | "toggle" | "next" | "previous" | "shuffleAll"}`,
`{"category": "albums" | "artists" | "songs" | "genres" | "playlists" | "folders"}`,
`{"page": "nowPlaying" | "queue" | "search" | "preferences" | "library"}`,
`{"target": "<path, file:// URL or <provider>:<id>>"}` (with `title`,
`artist`, `artUrl` for a stream), `{"search": "<text>"}`, and exhibition's
`{"windowType": "dockModeWindow", "dockMode": true}`.

## Layout

    appinfo.json              qml app, exhibition, mime types, permissions
    qml/main.qml              the window: stores, player, navigation, menus
    qml/Player.qml            the queue player: two engines, gain, crossfade
    qml/Engine.qml            one MediaPlayer with its volume factors
    qml/LibraryStore.qml      the indexer's songs (Db8Model), enriched by TagReader
    qml/StatsStore.qml        play counts, favourites, bookmarks (Db8Model)
    qml/PlaylistStore.qml     playlists (Db8Model)
    qml/StreamingStore.qml    the streaming services (daemon + Accounts)
    qml/SpotifyEngine.qml     Spotify through the daemon's librespot
    qml/NowPlaying.qml        Now Playing; LyricsView.qml its lyrics, LyricsLookup.qml LRCLIB's
    qml/Dashboard.qml         the dashboard
    qml/ExhibitionWindow.qml  exhibition's dock window; ExhibitionView.qml
    qml/pages, qml/views      library pages and the category views
    qml/components            rows, tiles, header, mini player, seek bar ...
    qml/js                    Queue.js, Library.js, Lyrics.js, Art.js, Streaming.js (plain logic)
    MusicApp/                 the C++ plugin (TagLib)
    tests/                    gtest, QML tests, build matrix, analysis
    tools/                    device install and tests, host screenshots,
                              the demo library (make-demo-library.sh)
    docs/screenshots/         the screenshots above

## Depends on

- Qt 6 (Quick, Multimedia with the GStreamer backend) and the GStreamer
  plugins for the formats; TagLib 2.
- luneos-components: the LuneOS Controls style, LuneOS.Forms, and from
  LuneOS.Components `ActionSheet`, `FastScroller` and `ConfirmDialog`
  (`acceptText`, `destructive`); from LuneOS.Service `Db8Model` with all
  pages, db8's errors and the writing calls (`allPages`, `status`,
  `error()`, `put`/`merge`/`del`/`putKind`) for the library, play counts
  and playlists.
- The media indexer, with a read grant on `com.palm.media.audio.file` for
  this app; without one the app asks through `com.palm.mediapermissions`.
- For streaming: the music streaming service (`luneos-synergy-music`) with
  its `/provider/<id>/resolve`, and a Synergy account per service.
- For Just Type: luna-universalsearchmgr registering apps' providers, and
  the launcher subscribing again when the search service restarts.
- For exhibition with the card open: a card shell that takes the app's
  dock window.

## Build

    cmake -S . -B build -G Ninja && ninja -C build

On LuneOS the recipe (`org.webosports.app.music.bb`) builds and installs it.
`tests/README.md` has the tests, the six-way build matrix, the static
analysis and the device tools.

## Licence

GPL-3.0-only (COPYING).
