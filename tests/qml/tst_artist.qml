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
import "../../qml/js/ArtistInfo.js" as ArtistInfo

/*
 * ArtistLookup against fake Wikidata, Wikipedia and Deezer: which item it
 * takes for the artist, what it makes of it, and what it remembers. The
 * answers are Wikidata's and Deezer's own, shortened.
 */
TestCase {
    name: "ArtistLookup"

    property var asked: []
    // Answers by the start of the URL asked: [status, json].
    property var answers: []
    function fake(url, done) {
        asked = asked.concat([url]);
        for (var i = 0; i < answers.length; i++) {
            if (url.indexOf(answers[i][0]) === 0)
                return done(answers[i][1], answers[i][2]);
        }
        done(404, null);
    }

    property var transportOverride: null
    ArtistLookup {
        id: lookup
        transport: function(url, done) { (transportOverride || fake)(url, done); }
        language: "en"
    }

    readonly property string wd: "https://www.wikidata.org/w/api.php?"
    function search(name) {
        return wd + "action=wbsearchentities&format=json&type=item&limit=10&language=en&uselang=en&search=" + encodeURIComponent(name);
    }
    function entity(id) {
        return wd + "action=wbgetentities&format=json&props=claims|sitelinks|descriptions&ids=" + id;
    }
    function labels(ids) {
        return wd + "action=wbgetentities&format=json&props=labels&ids=" + ids;
    }
    function claim(v) {
        return [{ rank: "normal", mainsnak: { datavalue: { value: v } } }];
    }
    function item(id) {
        return { id: id };
    }

    readonly property var queenSearch: ({ search: [
        { id: "Q193490", label: "Queen", description: "1973 debut studio album by Queen" },
        { id: "Q16511993", label: "queen", description: "female monarch" },
        { id: "Q15862", label: "Queen", description: "British musical group; rock band" }] })
    readonly property var queen: ({ entities: { Q15862: {
        descriptions: { en: { value: "British rock band" } },
        sitelinks: { enwiki: { title: "Queen (band)" } },
        claims: {
            P571: claim({ time: "+1970-01-01T00:00:00Z", precision: 9 }),
            P740: claim(item("Q84")),
            P495: claim(item("Q145")),
            P136: claim(item("Q11399")).concat(claim(item("Q49451"))),
            P2722: claim("412")
        } } } })
    readonly property var queenLabels: ({ entities: {
        Q84: { labels: { en: { value: "London" } } },
        Q11399: { labels: { en: { value: "rock music" } } },
        Q49451: { labels: { en: { value: "hard rock" } } } } })
    readonly property var queenWiki: ({ type: "standard", extract: "Queen are a British rock band formed in London in 1970.",
                                        thumbnail: { source: "https://upload.wikimedia.org/queen.jpg" } })
    readonly property var queenDeezer: ({ id: 412, name: "Queen", nb_fan: 12345678,
                                          picture_big: "https://cdn-images.dzcdn.net/queen-500.jpg" })

    function find(name) {
        var got = undefined, failed = undefined;
        lookup.find(name, function(info, f) { got = info; failed = f; });
        verify(got !== undefined, "answered at once by the fakes");
        return { info: got, failed: failed };
    }

    function init() {
        asked = [];
        answers = [];
        lookup.enabled = true;
        lookup._found = {};
        lookup._kept = 0;
    }

    function queenAnswers() {
        answers = [[search("Queen"), 200, queenSearch], [entity("Q15862"), 200, queen],
                   [labels("Q84|Q11399|Q49451"), 200, queenLabels],
                   ["https://en.wikipedia.org/api/rest_v1/page/summary/Queen_(band)", 200, queenWiki],
                   ["https://api.deezer.com/artist/412", 200, queenDeezer]];
    }

    function test_the_band_not_the_album_or_the_monarch() {
        queenAnswers();
        var r = find("Queen");
        compare(r.failed, false);
        compare(r.info.name, "Queen");
        compare(r.info.description, "British rock band");
        compare(r.info.bio, "Queen are a British rock band formed in London in 1970.");
        // Deezer's photo before Wikipedia's.
        compare(r.info.image, "https://cdn-images.dzcdn.net/queen-500.jpg");
        compare(r.info.fans, 12345678);
        compare(r.info.facts, [{ label: "Formed", value: "1970 · London" }, { label: "Genres", value: "rock music, hard rock" }]);
        compare(r.info.sources, ["Wikipedia", "Deezer"]);
        compare(asked.length, 5);
        // The next song by them: nothing asked.
        compare(find("queen").info.name, "Queen");
        compare(asked.length, 5);
    }

    function test_a_person_with_the_first_of_several_names() {
        answers = [[search("Tamia feat. Eric Benét"), 200, { search: [] }],
                   [search("Tamia"), 200, { search: [
                       { id: "Q271874", label: "Tamia", description: "Canadian musician and singer" }] }],
                   [entity("Q271874"), 200, { entities: { Q271874: {
                       descriptions: { en: { value: "Canadian musician and singer" } },
                       sitelinks: { enwiki: { title: "Tamia" } },
                       claims: { P569: claim({ time: "+1975-05-09T00:00:00Z", precision: 11 }), P19: claim(item("Q182625")),
                                 P571: claim({ time: "+1994-00-00T00:00:00Z", precision: 9 }) } } } }],
                   [labels("Q182625"), 200, { entities: { Q182625: { labels: { en: { value: "Windsor" } } } } }],
                   ["https://en.wikipedia.org/api/rest_v1/page/summary/Tamia", 200,
                    { extract: "Tamia is a Canadian singer.", thumbnail: { source: "https://upload.wikimedia.org/tamia.jpg" } }],
                   ["https://api.deezer.com/search/artist?limit=5&q=Tamia", 200, { data: [
                       { id: 9, name: "Tamia Hill" }, { id: 1609, name: "Tamia", nb_fan: 84512, picture_big: "" }] }]];
        var r = find("Tamia feat. Eric Benét");
        compare(r.info.name, "Tamia");
        // A person's career start is no "formed".
        compare(r.info.facts, [{ label: "Born", value: "9 May 1975 · Windsor" }]);
        compare(r.info.fans, 84512);
        // Deezer has no photo of her: Wikipedia's.
        compare(r.info.image, "https://upload.wikimedia.org/tamia.jpg");
        // Remembered under the whole name.
        find("Tamia feat. Eric Benét");
        compare(asked.length, 6);
    }

    function test_unreachable_is_said_and_asked_again() {
        answers = [[search("Queen"), 503, null]];
        var r = find("Queen");
        compare(r.info, null);
        compare(r.failed, true);
        find("Queen");
        compare(asked.length, 4, "each sent twice, and asked again");
    }

    // Wikimedia's odd 503: sent once more, and then it answers.
    function test_a_503_is_sent_once_more() {
        queenAnswers();
        var first = true;
        var all = answers;
        answers = [];
        transportOverride = function(url, done) {
            if (first && url.indexOf("wbsearchentities") > 0) {
                first = false;
                asked = asked.concat([url]);
                return done(503, null);
            }
            answers = all;
            fake(url, done);
        };
        var r = find("Queen");
        transportOverride = null;
        compare(r.failed, false);
        compare(r.info.name, "Queen");
        compare(asked.length, 6);
    }

    // Wikipedia down: what Wikidata and Deezer had is shown, but asked again.
    function test_a_source_failing_shows_the_rest() {
        queenAnswers();
        answers[3] = ["https://en.wikipedia.org/", 500, null];
        var r = find("Queen");
        compare(r.failed, true);
        compare(r.info.bio, "");
        compare(r.info.fans, 12345678);
        compare(r.info.sources, ["Deezer"]);
        find("Queen");
        compare(asked.length, 12);
    }

    function test_nobody_wikidata_knows_maybe_deezer_does() {
        answers = [[search("Obscure Act"), 200, { search: [{ id: "Q1", label: "Obscure Act", description: "2019 film" }] }],
                   ["https://api.deezer.com/search/artist", 200, { data: [{ id: 5, name: "obscure act", nb_fan: 12 }] }]];
        var r = find("Obscure Act");
        compare(r.info.fans, 12);
        compare(r.info.bio, "");
        compare(r.info.sources, ["Deezer"]);
        answers = [[search("Nobody"), 200, { search: [] }], ["https://api.deezer.com/search/artist", 200, { data: [] }]];
        r = find("Nobody");
        compare(r.info, null);
        compare(r.failed, false);
        find("Nobody");
        compare(asked.length, 4, "nothing found is remembered too");
    }

    // Deezer unreachable after Wikidata knew nobody: asked again next time.
    function test_deezer_failing_is_not_remembered() {
        answers = [[search("Obscure Act"), 200, { search: [] }], ["https://api.deezer.com/search/artist", 503, null]];
        var r = find("Obscure Act");
        compare(r.info, null);
        compare(r.failed, true);
        find("Obscure Act");
        compare(asked.length, 6);
    }

    function test_off_asks_nothing() {
        lookup.enabled = false;
        compare(find("Queen").info, null);
        compare(asked.length, 0);
    }

    // Wikipedia in the device's language where it has the artist.
    function test_the_wikipedia_of_the_language() {
        lookup.language = "nl";
        queenAnswers();
        answers[1] = [wd + "action=wbgetentities&format=json&props=claims|sitelinks|descriptions&ids=Q15862&languages=nl|en&sitefilter=nlwiki|enwiki",
                      200, { entities: { Q15862: { sitelinks: { enwiki: { title: "Queen (band)" }, nlwiki: { title: "Queen" } },
                                                   descriptions: { nl: { value: "Britse rockband" }, en: { value: "British rock band" } },
                                                   claims: {} } } }];
        answers.push(["https://nl.wikipedia.org/api/rest_v1/page/summary/Queen", 200, { extract: "Queen is een Britse rockband." }]);
        var r = find("Queen");
        lookup.language = "en";
        compare(r.info.description, "Britse rockband");
        compare(r.info.bio, "Queen is een Britse rockband.");
    }

    function test_names() {
        compare(ArtistInfo.names("Daft Punk feat. Pharrell Williams"), ["Daft Punk feat. Pharrell Williams", "Daft Punk"]);
        compare(ArtistInfo.names("Simon & Garfunkel"), ["Simon & Garfunkel", "Simon"]);
        compare(ArtistInfo.names("Lil Nas X"), ["Lil Nas X"]);
        compare(ArtistInfo.names("  "), []);
    }

    function test_dates_and_counts() {
        compare(ArtistInfo.dateText({ time: "+1975-05-09T00:00:00Z", precision: 11 }), "9 May 1975");
        compare(ArtistInfo.dateText({ time: "+1975-05-00T00:00:00Z", precision: 10 }), "May 1975");
        compare(ArtistInfo.dateText({ time: "+1970-01-01T00:00:00Z", precision: 9 }), "1970");
        compare(ArtistInfo.dateText({ time: "+1700-00-00T00:00:00Z", precision: 7 }), "");
        compare(ArtistInfo.dateText({ time: "-0500-00-00T00:00:00Z", precision: 9 }), "");
        compare(ArtistInfo.compactCount(12345678), "12.3M");
        compare(ArtistInfo.compactCount(845000), "845K");
        compare(ArtistInfo.compactCount(84512), "84.5K");
        compare(ArtistInfo.compactCount(932), "932");
        compare(ArtistInfo.compactCount(0), "");
    }

    function test_deprecated_claims_and_disambiguation_pages_are_left_out() {
        var f = ArtistInfo.facts({ claims: { P2722: [{ rank: "deprecated", mainsnak: { datavalue: { value: "1" } } }].concat(claim("2")) },
                                   sitelinks: {}, descriptions: {} }, "en");
        compare(f.deezerId, "2");
        compare(f.wikiTitle, "");
        var info = ArtistInfo.compose("X", f, {}, { type: "disambiguation", extract: "X may refer to:" }, null);
        compare(info, null);
    }
}
