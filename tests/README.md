# Music tests

## QML (`qml/`), on the build host

    tests/run-qml-tests.sh <host build dir> [luneos-components]

The host build is this project built for the host (`cmake -S . -B <dir>
-DBUILD_TESTING=ON`, TagLib from a sysroot works: see below); its plugin is
the real one. luneos-components needs its desktop build and the
`herrie/music-shared-parts` files.

- `tst_queue.qml`: `qml/js/Queue.js` - order, shuffle and unshuffle (with
  changes made meanwhile), repeat, play next, move, remove, save/restore.
- `tst_library.qml`: `qml/js/Library.js` and `Lyrics.js`, `Art.js` - the
  indexer's records, compilations, disc folders, album artists, system
  sounds and the indexer's "Unknown ..." stand-ins left out, sorting,
  search, the automatic playlists, formatting, LRC parsing.
- `tst_ui.qml`: the app itself against `fixtures/music` as the indexer would
  have stored it: library, covers (embedded, folder.jpg above a disc folder,
  none), every category, album page and playback, Now Playing (ReplayGain in
  every mode, lyrics, shuffle/repeat, favourite, cover tap regions), menus,
  queue, playlists, playlist files, search, folders, opening a file, launch
  actions and exhibition, preferences, song info, play counts, sleep timer
  and speed, the saved queue, and screenshots of every screen at 480x800,
  320x480, 720x720, 1024x768 and 768x1024 in `build/test-output/test-screens`.

- `tst_streaming.qml`: `qml/js/Streaming.js` (paths, track objects, which
  services count as signed in, what a playlist keeps, the queue keeping
  them), StreamingStore against a fake music streaming service (no daemon,
  providers, search, errors, resolve), Player resolving streamed tracks (to
  the fixture files), skipping one that does not resolve, and handing
  Spotify to SpotifyEngine and back, and SpotifyEngine's Connect calls and
  end-of-track guess (stopped near the end is an end, paused mid-track is
  not).
- `tst_ui.qml` `test_18_streaming`: the Streaming category, a service's
  search, playing a result, its menu, a playlist with a streamed track, and
  the per-service section in Search.

- `tst_ui.qml` also covers: a song the indexer lists whose file is gone
  (left out), the queue's header at 320 px (short labels, the summary on a
  line of its own), an album in a window wider than tall (the Q25's card:
  cover beside the text, Play and Shuffle on screen), the permission
  service not answering (an error with Try Again, not an endless
  spinner), and the dashboard's dismissed signal (main.qml pauses on it,
  which stops Spotify in librespot).

`fixtures/make-fixtures.sh` rebuilds the fixture library (ffmpeg, ImageMagick).
`tools/make-demo-library.sh` makes the larger demo library the README's
screenshots were taken with.

## Device-sized screenshots

    tools/screenshots-host.sh <host build dir> [luneos-components] [profile...]

Every screen at a device's screen size and grid unit (the stand-ins'
`--profile`: mindphone, q25, tp, n7), one contact sheet per device in
`build/test-output/screens`. qmltestrunner cannot pass the profile through,
hence the small runner `screens/main.cpp`.

## Unit tests (`unit/`), gtest

`tagcache.cpp` also checks that a file gone since it was cached comes back
as missing and leaves the cache. `tags.cpp` (fields, gains, numbers, years, embedded and folder covers, disc
folders, sidecar lyrics), `artwork.cpp` (keys, buckets, the image provider's
id round trip through QUrl, caching, the no-cover marker, a re-tagged file,
the accent colour), `tagcache.cpp` (the cache file, versions, enrich and
cancel), `playlistfiles.cpp` (M3U/PLS entries, Latin-1, M3U8 out, safe
names, writing confined to the export folder) and `filebrowser.cpp`
(listing, natural order, roots, the state file's names).

    tests/host-sysroot.sh <build TMPDIR> <sysroot>
    cmake -S . -B build/unit -G Ninja -DBUILD_TESTING=ON \
        -DCMAKE_TOOLCHAIN_FILE=tests/host-toolchain.cmake \
        -DTEST_SYSROOT=<sysroot> -DQT_HOST_PATH=<qtbase-native etc.>/usr
    ninja -C build/unit
    QT_PLUGIN_PATH=<sysroot>/usr/lib/plugins QT_QPA_PLATFORM=offscreen \
        <sysroot>/usr/lib/ld-linux-x86-64.so.2 --library-path <sysroot>/usr/lib \
        build/unit/tests/musicapp-tests

(set PKG_CONFIG_SYSROOT_DIR and PKG_CONFIG_LIBDIR to the sysroot for TagLib.)

Mutation-checked, 2026-10-18: each of these broke a test - gain range,
cover name preference, the single-image rule, file validity, the disc
folder cover, the no-cover marker, cache freshness, the tag cache's mtime
and version, skipping streams, the Latin-1 fallback, safe names, folders
first, natural order, empty mounts, state file names; in QML, keeping the
playing track on move, unshuffle, repeat one only at a track's end,
compilations, disc folders, articles in names, Memory Lane, the LRC offset,
the 30 s rule, a finished track not counted as a skip, the cover's tap
regions, album gain, saving the queue, merging the tag data. Two
mutations survived as equivalent: splitting the provider id at the last
"/" (both parts are percent-encoded, so there is only one) and dropping the
BOM strip (QString::fromUtf8 does it; the code was removed).

## Sanitizers and valgrind

ASan+UBSan with GCC (`-static-libasan -static-libubsan`) and Clang against
the same sysroot: clean. TSan: the sysroot's loader confuses TSan's thread
registry (an internal CHECK); built against the host's Qt instead it runs,
and reports four races, all on memory Qt hands between threads inside
libQt6Core (implicitly shared strings in the tag cache's maps, the thread
pool's runnable), which TSan cannot see synchronised because Qt itself is
not instrumented - false positives; no report touches the app's own shared
state (an atomic generation, a mutex around the cache file). Since the
missing-file test (2026-10-18) a run of the whole suite in one process can
also hit TSan's own thread-registry CHECK (`sanitizer_thread_registry.cpp:186`)
when the thread pool starts a thread; run in groups
(`--gtest_filter=TagReader.*` and `-TagReader.*`) every test passes, with
reports of the same kind only.

    valgrind --leak-check=full --errors-for-leak-kinds=definite \
        <sysroot>/usr/lib/ld-linux-x86-64.so.2 --library-path ... musicapp-tests

Clean with `JSIMD_FORCENONE=1 QT_ENABLE_REGEXP_JIT=0`: without them it
reports libjpeg-turbo's SIMD Huffman coder and PCRE2's JIT code, both known
false positives (nothing in the app's frames).

## Static analysis

    APP_SYSROOT=<sysroot> tests/static-analysis.sh

gcc `-fanalyzer` at -O0 and -O2, the clang analyzer with the alpha checkers,
clang-tidy (without the WebKit-only checks), cppcheck exhaustive and
inconclusive, flawfinder, Coccinelle: all clean. sparse parses C only.

## Six builds

    tests/build-matrix.sh <build TMPDIR> <Qt host dir> <work dir>

GCC and Clang for armv7 (the halium armv7 components, with a machine's
libhybris for EGL/GLES), aarch64 and x86-64, with `-Wall -Wextra -Wpedantic
-Wshadow -Wold-style-cast -Wcast-align` and more: no warnings in the app's
code.

## On a device

    tools/prepare-device.sh <serial> <luneos-components> <mediaindexer>
    tools/install.sh <build dir> <serial>
    tools/test-device.sh <serial> <name> [--with-fixtures]

`prepare-device.sh` puts the luneos-components additions and the indexer's
read grant on the device (keeping what it replaces) and refuses a device
whose luneos-components is older than the checkout. `install.sh` installs an
"Architecture: all" ipk through appInstallService and makes the hub rescan
the app's permissions (without it SAM's registerApp is denied and SAM closes
the app after each launch). `test-device.sh` checks that Shuffle All plays
(a PulseAudio stream from qml-runner) and keeps playing with the card in the
background, and takes screenshots of the screens.

Streaming on the mindphone, 2026-10-18, with luneos-synergy-music built
from `herrie/music-resolve`: the Internet Archive and YouTube searched; an
Archive track resolved and played by the app (`{"target":"archive:<id>"}`,
a qml-runner stream in PulseAudio). YouTube resolved, but its upstream
answered 403 after the first MiB (the daemon's known YouTube problem,
recorded in luneos-synergy-connectors' tests), so it did not play. Spotify,
Tidal, Deezer, Qobuz and Apple need accounts and were not tried.

Screenshots 2026-10-18 on all three (docs/screenshots), with the demo
library: the mindphone (armv7, 480x800), the Q25 (aarch64, 720x720) and
the TouchPad (armv7, 1024x768, luneos-components 8d1e0bb installed for it).
On the TouchPad the root file system was 96% full, db8 refused every write
("quota exceeded", its space alert at 95%) and stayed refusing after space
was freed, until db8-maindb was restarted; the app then hid the indexer's
stale records for files moved away. Not shot: exhibition on the Q25 and
TouchPad (their dock window is shown only in real dock mode) and the
dashboard (the card could not be sent to the background by launch).

Passed 2026-10-18 on the mindphone (armv7, 480x800, 482 songs) and the Q25
(aarch64, 720x720). Not run: the TouchPad (its luneos-components predates
the shared parts this needs); exhibition in dock mode (the carousel needs a
swipe, and injected touches did not reach the mindphone's shell).
