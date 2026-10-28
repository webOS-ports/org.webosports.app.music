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

import "js/ArtistInfo.js" as ArtistInfo

/*
 * Who the playing artist is, from open sources asked with the artist's
 * name: Wikidata says which artist it is, with its dates, origin and
 * genres; Wikipedia has the story and a photo; Deezer's public catalogue
 * the fans and a better photo (by the Deezer id Wikidata has, else by the
 * name). No account and no key.
 */
QtObject {
    id: lookup

    // The preference: off, nothing is looked up.
    property bool enabled: true
    // The language of the Wikipedia to read, where it has the artist ("C"
    // and the like, no language: English).
    property string language: {
        var l = Qt.locale().name.split("_")[0];
        return /^[a-z]{2,3}$/.test(l) ? l : "en";
    }
    property string wikidataUrl: "https://www.wikidata.org/w/api.php"
    property string deezerUrl: "https://api.deezer.com"
    // function(url, done(httpStatus, jsonOrNull)): the HTTP call, replaceable
    // by the tests.
    property var transport: _xhr
    // Wikimedia answers 503 now and then: a request that failed so (or did
    // not get through at all) is sent once more before it counts as failed.
    function _get(url, done) {
        transport(url, function(status, data) {
            if (status === 0 || status >= 500)
                transport(url, done);
            else
                done(status, data);
        });
    }

    // What was found (or that nothing was) per artist, so the next song by
    // them does not ask again; a failed request is not kept.
    property var _found: ({})
    property int _kept: 0

    /* done(info, failed): ArtistInfo.compose()'s info, or null when nothing
     * is known; failed when a source could not be reached (it is asked again
     * next time). */
    function find(artist, done) {
        var tried = ArtistInfo.names(artist);
        if (!enabled || tried.length === 0) {
            done(null, false);
            return;
        }
        var key = tried[0].toLowerCase();
        if (_found.hasOwnProperty(key)) {
            done(_found[key], false);
            return;
        }
        var tryName = function(i) {
            if (i >= tried.length) {
                // Nobody Wikidata knows: Deezer may still, by the whole name.
                lookup._deezerByName(tried[0], function(dz, failed) {
                    var info = ArtistInfo.compose(tried[0], null, null, null, dz);
                    if (!failed)
                        lookup._keep(key, info);
                    done(info, failed);
                });
                return;
            }
            lookup._wikidataSearch(tried[i], function(id, failed) {
                if (failed) {
                    done(null, true);
                } else if (id === "") {
                    tryName(i + 1);
                } else {
                    lookup._about(tried[i], id, function(info, failed) {
                        if (!failed)
                            lookup._keep(key, info);
                        done(info, failed);
                    });
                }
            });
        };
        tryName(0);
    }

    function _wikidataSearch(name, done) {
        _get(wikidataUrl + "?action=wbsearchentities&format=json&type=item&limit=10&language=en&uselang=en&search="
                  + encodeURIComponent(name), function(status, data) {
            if (status !== 200 || !data)
                done("", true);
            else
                done(ArtistInfo.pickEntity(data, name), false);
        });
    }

    // The item's facts, then its labels, Wikipedia page and Deezer artist
    // side by side.
    function _about(name, id, done) {
        var lang = language;
        var langs = lang === "en" ? "en" : lang + "|en";
        _get(wikidataUrl + "?action=wbgetentities&format=json&props=claims|sitelinks|descriptions&ids=" + id
                  + "&languages=" + langs + "&sitefilter=" + (lang === "en" ? "enwiki" : lang + "wiki|enwiki"),
                  function(status, data) {
            var entity = status === 200 && data && data.entities ? data.entities[id] : null;
            if (!entity) {
                done(null, true);
                return;
            }
            var f = ArtistInfo.facts(entity, lang);
            var labels = {}, wiki = null, dz = null, failed = false;
            var pending = 3;
            var joined = function() {
                if (--pending === 0)
                    done(ArtistInfo.compose(name, f, labels, wiki, dz), failed);
            };
            var ids = [f.placeId].concat(f.genreIds).filter(function(x) { return x !== ""; });
            if (ids.length === 0) {
                joined();
            } else {
                lookup._get(lookup.wikidataUrl + "?action=wbgetentities&format=json&props=labels&ids=" + ids.join("|")
                                 + "&languages=" + langs, function(status, data) {
                    if (status === 200 && data)
                        ids.forEach(function(x) { labels[x] = ArtistInfo.label(data, x, lang); });
                    else
                        failed = true;
                    joined();
                });
            }
            if (f.wikiTitle === "") {
                joined();
            } else {
                lookup._get("https://" + f.wikiLang + ".wikipedia.org/api/rest_v1/page/summary/"
                                 + encodeURIComponent(f.wikiTitle.replace(/ /g, "_")), function(status, data) {
                    if (status === 200 && data)
                        wiki = data;
                    else if (status !== 404)
                        failed = true;
                    joined();
                });
            }
            var deezerDone = function(artist, dzFailed) {
                dz = artist;
                failed = failed || dzFailed;
                joined();
            };
            if (f.deezerId !== "") {
                lookup._get(lookup.deezerUrl + "/artist/" + encodeURIComponent(f.deezerId), function(status, data) {
                    if (status === 200)
                        deezerDone(ArtistInfo.deezerArtist(data), false);
                    else
                        deezerDone(null, true);
                });
            } else {
                lookup._deezerByName(name, deezerDone);
            }
        });
    }

    function _deezerByName(name, done) {
        _get(deezerUrl + "/search/artist?limit=5&q=" + encodeURIComponent(name), function(status, data) {
            if (status === 200)
                done(ArtistInfo.pickDeezer(data, name), false);
            else
                done(null, true);
        });
    }

    function _keep(key, info) {
        if (_kept >= 100) {
            _found = {};
            _kept = 0;
        }
        _found[key] = info;
        _kept++;
    }

    function _xhr(url, done) {
        var req = new XMLHttpRequest();
        req.onreadystatechange = function() {
            if (req.readyState !== XMLHttpRequest.DONE)
                return;
            var data = null;
            try {
                data = req.responseText ? JSON.parse(req.responseText) : null;
            } catch (e) {
                data = null;
            }
            done(req.status, data);
        };
        req.open("GET", url);
        // Wikimedia asks its clients to say who they are.
        req.setRequestHeader("User-Agent", "Music for LuneOS (https://github.com/webOS-ports/org.webosports.app.music)");
        req.setRequestHeader("Api-User-Agent", "Music for LuneOS (https://github.com/webOS-ports/org.webosports.app.music)");
        req.send();
    }
}
