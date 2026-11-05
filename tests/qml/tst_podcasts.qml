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
import QtTest

import "../../qml"
import "../../qml/js/Podcasts.js" as Podcasts

/*
 * Podcasts: episodes as tracks and what is said of them (js/Podcasts.js),
 * and PodcastStore against a fake music streaming service.
 */
Item {
    id: root
    width: 200
    height: 200

    property var calls: []
    property var answers: ({})
    function fakeTransport(method, url, body, done) {
        var path = url.replace(/^http:\/\/127\.0\.0\.1:8730/, "");
        root.calls = root.calls.concat([{ method: method, path: path, body: body }]);
        var a = root.answers[method + " " + path.replace(/\?.*$/, "")];
        if (a === undefined)
            done(404, { error: "no such route" });
        else
            done(a.code, a.json);
    }

    PodcastStore {
        id: store
        transport: root.fakeTransport
    }

    function episode(id, extra) {
        var e = { id: "podcast:aaaaaaaaaaaa." + id, podcast: "aaaaaaaaaaaa", podcastTitle: "The Show", title: "Episode " + id,
                  published: Date.UTC(2026, 10, 3, 12), duration_ms: 3600000, url: "https://x.example/" + id + ".mp3",
                  type: "audio/mpeg", video: false, description: "", image: "https://x.example/i.jpg",
                  position_ms: 0, played: false, "new": false, lastPlayed: 0, download: { state: "none", progress: 0 } };
        for (var k in extra)
            e[k] = extra[k];
        return e;
    }

    TestCase {
        name: "Podcasts"

        function init() {
            root.calls = [];
            root.answers = {};
        }

        function test_track() {
            var t = Podcasts.track(episode("1", { video: true }));
            compare(t.path, "podcast:aaaaaaaaaaaa.1");
            compare(t.artist, "The Show");
            compare(t.album, "The Show");
            compare(t.genre, "Podcast");
            compare(t.duration, 3600000);
            compare(t.provider, "podcast");
            verify(t.remote);
            verify(t.video);
            compare(t.artUrl, "https://x.example/i.jpg");
            verify(Podcasts.isEpisode(t.path));
            verify(!Podcasts.isEpisode("radio:rb.x"));
            verify(!Podcasts.isEpisode(""));
        }

        function test_detail() {
            var now = Date.UTC(2026, 10, 5);
            compare(Podcasts.dateOf(Date.UTC(2026, 10, 3, 12), now), "3 Nov");
            compare(Podcasts.dateOf(Date.UTC(2024, 0, 9, 12), now), "9 Jan 2024");
            compare(Podcasts.dateOf(0, now), "");
            compare(Podcasts.detailOf(episode("1"), now, false), "3 Nov · 1 h 00 min");
            compare(Podcasts.detailOf(episode("1", { position_ms: 600000 }), now, true), "The Show · 3 Nov · 50 min left");
            compare(Podcasts.detailOf(episode("1", { played: true, position_ms: 5 }), now, false), "3 Nov · Played");
            compare(Podcasts.detailOf(episode("1", { duration_ms: 0, position_ms: 5000 }), now, false), "3 Nov · Started");
            compare(Podcasts.detailOf(episode("1", { download: { state: "downloading", progress: 0.426 } }), now, false),
                    "3 Nov · 1 h 00 min · Downloading 43%");
            compare(Podcasts.detailOf(episode("1", { download: { state: "done" }, video: true }), now, false),
                    "3 Nov · 1 h 00 min · Downloaded · Video");
            compare(Podcasts.downloadOf(episode("1", { download: { state: "queued" } })), "Waiting to download");
            compare(Podcasts.downloadOf(episode("1", { download: { state: "failed" } })), "Download failed");
            compare(Podcasts.downloadOf({}), "");
            compare(Podcasts.fractionOf(episode("1", { position_ms: 900000 })), 0.25);
            compare(Podcasts.fractionOf(episode("1", { position_ms: 900000, played: true })), 0);
            compare(Podcasts.fractionOf(episode("1", { duration_ms: 0, position_ms: 9 })), 0);
        }

        function test_podcast_detail() {
            compare(Podcasts.podcastDetail({ newCount: 2, episodeCount: 30 }), "2 new · 30 episodes");
            compare(Podcasts.podcastDetail({ newCount: 0, episodeCount: 1 }), "1 episode");
            compare(Podcasts.podcastDetail({ newCount: 0, episodeCount: 3, lastError: "404" }), "Cannot be read");
            compare(Podcasts.downloadsDetail([episode("1", { download: { state: "done" } }), episode("2", { download: { state: "done" } }),
                                              episode("3", { download: { state: "downloading" } }),
                                              episode("4", { download: { state: "queued" } }),
                                              episode("5", { download: { state: "failed" } })]),
                    "2 downloaded · 2 downloading · 1 failed");
            compare(Podcasts.downloadsDetail([]), "");
        }

        function test_feed_address() {
            compare(Podcasts.feedAddressOf("radiolab"), "");
            compare(Podcasts.feedAddressOf("two words.com/x"), "");
            compare(Podcasts.feedAddressOf(" https://feeds.example.com/show "), "https://feeds.example.com/show");
            compare(Podcasts.feedAddressOf("http://feeds.example.com/show.xml"), "http://feeds.example.com/show.xml");
            compare(Podcasts.feedAddressOf("feed://x.org/rss"), "https://x.org/rss");
            compare(Podcasts.feedAddressOf("itpc://x.org/rss"), "https://x.org/rss");
            compare(Podcasts.feedAddressOf("pcast:https://x.org/rss"), "https://x.org/rss");
            compare(Podcasts.feedAddressOf("feeds.npr.org/510289/podcast.xml"), "https://feeds.npr.org/510289/podcast.xml");
            compare(Podcasts.feedAddressOf("a.b"), "");
            compare(Podcasts.feedAddressOf("http://localhost/x"), "");
        }

        function test_labels() {
            compare(Podcasts.refreshLabel(0), "Only when asked");
            compare(Podcasts.refreshLabel(1), "Every hour");
            compare(Podcasts.refreshLabel(6), "Every 6 hours");
            compare(Podcasts.autoDownloadLabel(0), "Off");
            compare(Podcasts.autoDownloadLabel(1), "The newest episode");
            compare(Podcasts.autoDownloadLabel(3), "The newest 3");
            compare(Podcasts.keepLabel(0), "Keep them");
            compare(Podcasts.keepLabel(1), "After a day");
            compare(Podcasts.keepLabel(7), "After 7 days");
            compare(Podcasts.importSummary({ added: 3, skipped: 1, failed: [{ url: "x" }] }),
                    "Subscribed to 3 podcasts; 1 was there already; 1 cannot be read.");
            compare(Podcasts.importSummary({ added: 0, skipped: 2, failed: [] }), "No new podcasts; 2 were there already.");
            compare(Podcasts.importSummary({ added: 1 }), "Subscribed to 1 podcast.");
            compare(Podcasts.errorOf(0, null), "The music streaming service is not running.");
            compare(Podcasts.errorOf(502, { error: "The feed did not answer." }), "The feed did not answer.");
            compare(Podcasts.errorOf(500, null), "The music streaming service could not do that (500).");
        }

        // The store: unavailable without the service, its lists and where
        // each episode was left once it answers, the polling while it works.
        function test_store_refresh() {
            store.status = "unknown";
            store.refresh();
            compare(store.status, "unavailable");
            verify(!store.available);
            var started = episode("2", { position_ms: 120000 });
            root.answers = {
                "GET /podcasts": { code: 200, json: { podcasts: [{ id: "aaaaaaaaaaaa", url: "https://x.example/feed", title: "The Show",
                                                                   newCount: 1, episodeCount: 2 }],
                                                      refreshing: true, downloading: 1 } },
                "GET /podcasts/settings": { code: 200, json: { refreshHours: 3, wifiOnly: false, autoDownload: 2, keepPlayedDays: 0, notify: false } },
                "GET /podcasts/new": { code: 200, json: { episodes: [episode("1", { "new": true })] } },
                "GET /podcasts/inprogress": { code: 200, json: { episodes: [started] } },
                "GET /podcasts/downloads": { code: 200, json: { episodes: [episode("3", { download: { state: "downloading" }, played: true, position_ms: 9 })] } }
            };
            var rev = store.revision;
            store.refresh();
            compare(store.status, "ready");
            verify(store.available);
            compare(store.podcasts.length, 1);
            verify(store.refreshing);
            compare(store.downloading, 1);
            compare(store.settings.refreshHours, 3);
            compare(store.newEpisodes.length, 1);
            compare(store.inProgress[0].id, started.id);
            compare(store.downloads.length, 1);
            verify(store.revision >= rev + 3);
            compare(store.positionOf(started.id), 120000);
            // Played: it starts from the beginning.
            compare(store.positionOf("podcast:aaaaaaaaaaaa.3"), 0);
            compare(store.positionOf("podcast:unknown.x"), 0);
            compare(store.podcast("aaaaaaaaaaaa").title, "The Show");
            compare(store.podcast("bbbbbbbbbbbb"), null);
            compare(store.subscribedId("https://x.example/feed"), "aaaaaaaaaaaa");
            compare(store.subscribedId("https://other/feed"), "");
            // Settings the service does not have keep what was there.
            root.answers["GET /podcasts/settings"] = { code: 200, json: { error: "x" } };
            store.refresh();
            compare(store.settings.refreshHours, 3);
            // While it refreshes or downloads, it is asked again by itself.
            root.calls = [];
            wait(2300);
            verify(root.calls.some(function(c) { return c.path === "/podcasts"; }));
            root.answers["GET /podcasts"] = { code: 200, json: { podcasts: [], refreshing: false, downloading: 0 } };
            store.refresh();
            root.calls = [];
            wait(2300);
            verify(!root.calls.some(function(c) { return c.path === "/podcasts"; }));
        }

        function test_store_calls() {
            root.answers = {
                "GET /podcasts/search": { code: 200, json: { results: [{ title: "Radiolab", url: "https://r.example/feed" }] } },
                "POST /podcasts/preview": { code: 200, json: { podcast: { title: "P" }, episodes: [episode("7", { position_ms: 5000 })] } },
                "POST /podcasts/state": { code: 200, json: { episode: episode("1", { position_ms: 61000 }) } },
                "GET /podcasts/episodes": { code: 200, json: { podcast: {}, episodes: [episode("1")], more: true, next: 50 } },
                "POST /podcasts/resolve": { code: 200, json: { url: "file:///media/internal/podcasts/The Show/a.mp3", video: false } },
                "POST /podcasts/opml/import": { code: 200, json: { added: 1, skipped: 0, failed: [] } },
                "POST /podcasts/opml/export": { code: 200, json: { path: "/media/internal/podcasts/podcasts.opml" } },
                "GET /podcasts/opml/files": { code: 200, json: { files: [{ path: "/media/internal/a.opml", name: "a.opml" }] } },
                "POST /podcasts/settings": { code: 200, json: { refreshHours: 12, wifiOnly: true, autoDownload: 0, keepPlayedDays: 7, notify: true } }
            };
            var got = null;
            store.search("radio lab", function(list, err) { got = list; });
            compare(got.length, 1);
            verify(root.calls[0].path.indexOf("q=radio%20lab") >= 0);
            store.preview("https://p.example/feed", function(data) { got = data; });
            compare(got.podcast.title, "P");
            compare(root.calls[root.calls.length - 1].body.url, "https://p.example/feed");
            compare(store.positionOf("podcast:aaaaaaaaaaaa.7"), 5000);
            // A position is known at once, before the service answered.
            store.setState("podcast:aaaaaaaaaaaa.1", { position_ms: 60000 });
            var post = root.calls.filter(function(c) { return c.path === "/podcasts/state"; })[0];
            compare(post.body.id, "podcast:aaaaaaaaaaaa.1");
            compare(post.body.position_ms, 60000);
            compare(store.positionOf("podcast:aaaaaaaaaaaa.1"), 61000);
            store.setState("podcast:aaaaaaaaaaaa.9", { played: true });
            compare(store.positionOf("podcast:aaaaaaaaaaaa.9"), 0);
            var next = 0;
            store.episodes("aaaaaaaaaaaa", 0, function(list, err, n) { got = list; next = n; });
            compare(got.length, 1);
            compare(next, 50);
            root.answers["GET /podcasts/episodes"] = { code: 200, json: { episodes: [episode("2")], more: false, next: 0 } };
            store.episodes("aaaaaaaaaaaa", 50, function(list, err, n) { next = n; });
            compare(next, -1);
            verify(root.calls[root.calls.length - 1].path.indexOf("offset=50") >= 0);
            var url = "", video = true;
            store.resolve({ path: "podcast:aaaaaaaaaaaa.1" }, function(u, err, v) { url = u; video = v; });
            compare(url, "file:///media/internal/podcasts/The Show/a.mp3");
            verify(!video);
            compare(root.calls.filter(function(c) { return c.path === "/podcasts/resolve"; })[0].body.trackId, "aaaaaaaaaaaa.1");
            root.answers["POST /podcasts/resolve"] = { code: 404, json: { error: "No such episode." } };
            var error = "";
            store.resolve({ path: "podcast:aaaaaaaaaaaa.x" }, function(u, err) { url = u; error = err; });
            compare(url, "");
            compare(error, "No such episode.");
            store.importOpml({ path: "/media/internal/a.opml" }, function(r) { got = r; });
            compare(got.added, 1);
            store.exportOpml(function(path) { got = path; });
            compare(got, "/media/internal/podcasts/podcasts.opml");
            store.opmlFiles(function(files) { got = files; });
            compare(got[0].name, "a.opml");
            store.saveSettings({ refreshHours: 12 });
            compare(store.settings.refreshHours, 12);
            compare(root.calls.filter(function(c) { return c.path === "/podcasts/settings" && c.method === "POST"; })[0].body.refreshHours, 12);
        }
    }
}
