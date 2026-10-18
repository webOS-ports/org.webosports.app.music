# Music - LuneOS

The LuneOS music player: a QML app (`"type": "qml"`, run by qml-runner) with
a C++ plugin (`MusicApp/`, TagLib). See README.md for what it does and
tests/README.md for every test and check.

## Conventions

- App id `org.webosports.app.music`; author, committer and Signed-off-by
  `Herman van Hazendonk <github.com@herrie.org>`; no Co-Authored-By trailers.
- Structure, tests and tools follow org.webosports.app.soundrecorder.
- Reuse luneos-components (LuneOS.Forms, LuneOS.Components, the LuneOS
  Controls style) and add generic parts there (ActionSheet, FastScroller came
  from this app) rather than keeping app-local copies.
- Library light (LuneOS.Forms colours), player dark - palm-dark, as the
  legacy Music app. No Back keys: every LuneOS device has the back gesture
  (Escape).
- Every screen must look right at 480x800 (mindphone), 720x720 (Q25) and
  1024x768 (TouchPad), portrait and landscape: run
  `tools/screenshots-host.sh` (device grid units) and look at the sheets.
  Exhibition is sized from the screen, not grid units.
- No glyphs the devices' Prelude font lacks (U+25BE, U+25B6, U+2665,
  U+2713 among them): use the SVGs in qml/images.
- Plain logic goes in qml/js (tested by tst_queue/tst_library); C++ in
  MusicApp/ gets gtest coverage and must stay clean in the build matrix
  (GCC + Clang, armv7/aarch64/x86-64) and tests/static-analysis.sh.

## Platform facts this relies on

- The media indexer writes `com.palm.media.audio.file:1` but no covers, no
  lengths (0), no years, and "Unknown Title/Artist/Album/Genre" for missing
  tags; `modifiedTime` is in seconds. The app fills the gaps with TagLib.
- Reading the indexer's kind needs the static grant (mediaindexer
  files/db8/permissions) or `com.palm.mediapermissions/request`.
- requiredPermissions must include `application.operation` (qml-runner
  registers the app with SAM under the app's own name). After a developer
  install the hub must rescan (`ls-control scan-volatile-dirs`;
  tools/install.sh does it) or every call is denied and SAM closes the app.
- Toasts must be `type: "light"`, or the shell keeps an entry for each.
- The exhibition carousel launches the app with
  `{"windowType":"dockModeWindow","dockMode":true}` and takes its dock window
  (a card shell that prefers the dock window over the open card).
- No MPRIS or media keys in the shell; the dashboard is a floating window.
- Streaming goes through luneos-synergy-music (luneos-synergy-connectors
  music/_core/service): `/providers`, `/provider/<id>/search`,
  `/provider/<id>/resolve` (the app plays the URL), `/player/*` for
  Spotify's librespot. A service counts only when its Synergy account
  (template org.webosports.app.music.<id>) exists: `listAccounts` (needs
  `accountsservice.operation`; `listAccountsPublic` is denied to apps).
- Just Type providers in appinfo.json are only registered by a
  luna-universalsearchmgr that reads apps' providers from SAM (older images
  list none, not even Calendar's).
- db8 goes through LuneOS.Service's `Db8Model` (all pages, db8's error
  codes, put/merge/del/putKind): no app-local db8 helper.
- Eos.Window 0.1 on the devices has no `onClosing` (the desktop stand-in
  does): a handler for it makes main.qml fail to load.
- /media/internal is vfat on some devices (the TouchPad): `music` and
  `Music` are the same folder.
- db8 refuses all writes ("quota exceeded") once its volume is 95% full,
  and on current images keeps refusing after space is freed until it is
  restarted.
