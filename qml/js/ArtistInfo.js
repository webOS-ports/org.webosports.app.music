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

.pragma library

/*
 * What ArtistLookup makes of Wikidata's, Wikipedia's and Deezer's answers:
 * which of Wikidata's search results is the artist, the facts of its item,
 * and how they read.
 */

var _months = ["January", "February", "March", "April", "May", "June", "July",
               "August", "September", "October", "November", "December"];

// What Wikidata says a musician, a band or the like is (its English
// description): "Canadian musician and singer", "British rock band".
var _musical = /\b(music|musical|musician|singer|songwriter|band|group|duo|trio|quartet|rapper|hip hop|dj|disc jockey|composer|producer|vocalist|guitarist|pianist|drummer|bassist|violinist|cellist|saxophonist|trumpeter|orchestra|ensemble|choir|conductor|artist|mc|record)\b/i;

function _norm(s) {
    return String(s || "").toLowerCase().replace(/[‘’`]/g, "'").replace(/\s+/g, " ").trim();
}

/* The names to look an artist up by, best first: the whole of it, then the
 * first of several ("Daft Punk feat. Pharrell Williams", "A, B", "A & B"). */
function names(artist) {
    var whole = String(artist || "").trim();
    if (whole === "")
        return [];
    var out = [whole];
    var first = whole.split(/\s+(?:feat\.?|ft\.?|featuring|with|x|vs\.?)\s+|\s*[,;/]\s*|\s+&\s+/i)[0].trim();
    if (first !== "" && first !== whole)
        out.push(first);
    return out;
}

/* Of Wikidata's wbsearchentities answer, the id of the item named name
 * (by its label or an alias) that is a musician, a band or the like; "" for
 * none. */
function pickEntity(reply, name) {
    var results = reply && Array.isArray(reply.search) ? reply.search : [];
    var want = _norm(name);
    for (var i = 0; i < results.length; i++) {
        var r = results[i];
        if (!r || !r.id)
            continue;
        var named = _norm(r.label) === want || (r.match && _norm(r.match.text) === want);
        if (named && _musical.test(String(r.description || "")))
            return r.id;
    }
    return "";
}

function _values(claims, property) {
    var list = claims && Array.isArray(claims[property]) ? claims[property] : [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var snak = list[i] && list[i].mainsnak;
        if (list[i].rank !== "deprecated" && snak && snak.datavalue && snak.datavalue.value !== undefined)
            out.push(snak.datavalue.value);
    }
    return out;
}

function _ids(claims, property, max) {
    return _values(claims, property).map(function(v) { return v && v.id ? v.id : ""; })
                                    .filter(function(id) { return id !== ""; }).slice(0, max);
}

function _first(claims, property) {
    var v = _values(claims, property);
    return v.length ? v[0] : null;
}

/*
 * The facts of a Wikidata item (an entity of wbgetentities): {
 *   description,
 *   wikiTitle, wikiLang - its Wikipedia article, in lang if there is one,
 *   born, died, formed, disbanded - Wikidata times ({ time, precision }) or null,
 *   placeId - where born, or where formed (else its country),
 *   genreIds,
 *   deezerId
 * }. labels are fetched for placeId and genreIds afterwards.
 */
function facts(entity, lang) {
    var claims = entity && entity.claims ? entity.claims : {};
    var links = entity && entity.sitelinks ? entity.sitelinks : {};
    var descs = entity && entity.descriptions ? entity.descriptions : {};
    var wikiLang = links[lang + "wiki"] ? lang : (links.enwiki ? "en" : "");
    var desc = descs[lang] || descs.en;
    var born = _first(claims, "P569");
    var formedAt = _ids(claims, "P740", 1);
    var origin = _ids(claims, "P495", 1);
    var birthPlace = _ids(claims, "P19", 1);
    var place = born ? birthPlace : (formedAt.length ? formedAt : origin);
    var deezer = _first(claims, "P2722");
    return {
        description: desc ? String(desc.value || "") : "",
        wikiTitle: wikiLang ? String(links[wikiLang + "wiki"].title || "") : "",
        wikiLang: wikiLang,
        born: born,
        died: _first(claims, "P570"),
        formed: born ? null : _first(claims, "P571"),
        disbanded: born ? null : _first(claims, "P576"),
        placeId: place.length ? place[0] : "",
        genreIds: _ids(claims, "P136", 4),
        deezerId: deezer !== null ? String(deezer) : ""
    };
}

/* An entity's label from wbgetentities' labels answer, in lang or English. */
function label(reply, id, lang) {
    var e = reply && reply.entities ? reply.entities[id] : null;
    var l = e && e.labels ? (e.labels[lang] || e.labels.en) : null;
    return l ? String(l.value || "") : "";
}

/* A Wikidata time as text, as precise as it is: "9 May 1975", "May 1975",
 * "1970"; "" for none or one before the year 1. */
function dateText(t) {
    if (!t || typeof t.time !== "string")
        return "";
    var m = /^\+(\d+)-(\d\d)-(\d\d)/.exec(t.time);
    if (!m)
        return "";
    var year = parseInt(m[1], 10), month = parseInt(m[2], 10), day = parseInt(m[3], 10);
    if (t.precision >= 11 && month >= 1 && day >= 1)
        return day + " " + _months[month - 1] + " " + year;
    if (t.precision === 10 && month >= 1)
        return _months[month - 1] + " " + year;
    return t.precision >= 9 ? String(year) : "";
}

/* 1234567 -> "1.2M", 84500 -> "84.5K", 932 -> "932". */
function compactCount(n) {
    n = Math.floor(Number(n) || 0);
    if (n <= 0)
        return "";
    var unit = n >= 1e9 ? [1e9, "B"] : n >= 1e6 ? [1e6, "M"] : n >= 1e3 ? [1e3, "K"] : null;
    if (!unit)
        return String(n);
    var v = n / unit[0];
    return (v >= 100 ? Math.floor(v) : Math.floor(v * 10) / 10) + unit[1];
}

/* Of Deezer's /search/artist answer, the artist named name: { id, fans,
 * picture }, else null. */
function pickDeezer(reply, name) {
    var list = reply && Array.isArray(reply.data) ? reply.data : [];
    var want = _norm(name);
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id && _norm(list[i].name) === want)
            return deezerArtist(list[i]);
    }
    return null;
}

/* Deezer's artist object as { id, fans, picture }; null for none (or its error). */
function deezerArtist(a) {
    if (!a || !a.id || a.error)
        return null;
    return { id: String(a.id), fans: Number(a.nb_fan) || 0, picture: String(a.picture_big || a.picture_medium || "") };
}

/*
 * Who an artist is, from what was found: { name, description, bio, image,
 * facts: [{ label, value }], fans, sources: ["Wikipedia", "Deezer"] }; null
 * when nothing was.
 *   f: facts() or null; labels: { id: label }; wiki: Wikipedia's page
 *   summary or null; deezer: deezerArtist() or null.
 */
function compose(name, f, labels, wiki, deezer) {
    labels = labels || {};
    var bio = wiki && wiki.type !== "disambiguation" ? String(wiki.extract || "") : "";
    var out = {
        name: name,
        description: f ? f.description : "",
        bio: bio,
        image: "",
        facts: [],
        fans: deezer ? deezer.fans : 0,
        sources: []
    };
    if (deezer && deezer.picture)
        out.image = deezer.picture;
    else if (bio !== "" && wiki.thumbnail && wiki.thumbnail.source)
        out.image = String(wiki.thumbnail.source);
    if (f) {
        var place = labels[f.placeId] || "";
        var when = function(t, where) {
            var d = dateText(t);
            return where && d ? d + " · " + where : (d || where || "");
        };
        if (f.born)
            out.facts.push({ label: "Born", value: when(f.born, place) });
        if (f.died)
            out.facts.push({ label: "Died", value: dateText(f.died) });
        if (f.formed || (!f.born && place))
            out.facts.push({ label: "Formed", value: when(f.formed, place) });
        if (f.disbanded)
            out.facts.push({ label: "Disbanded", value: dateText(f.disbanded) });
        var genres = f.genreIds.map(function(id) { return labels[id] || ""; })
                               .filter(function(g) { return g !== ""; });
        if (genres.length)
            out.facts.push({ label: genres.length > 1 ? "Genres" : "Genre", value: genres.join(", ") });
        out.facts = out.facts.filter(function(x) { return x.value !== ""; });
    }
    if (bio !== "")
        out.sources.push("Wikipedia");
    if (deezer)
        out.sources.push("Deezer");
    if (out.bio === "" && out.description === "" && out.facts.length === 0 && !deezer)
        return null;
    return out;
}
