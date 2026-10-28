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
 * The source of a cover Image: image://musicart/<album>/<path>, the album
 * first so the C++ side (ArtworkStore::parseId) can split at the first "/"
 * - encodeURIComponent turns any "/" in the album name into %2F. A
 * streamed track (a "<provider>:<id>" path) has no file to look in: its
 * artUrl, or nothing.
 */
function source(path, album, artUrl) {
    // A streamed track's cover is on the web.
    if (artUrl)
        return artUrl;
    if (!path || /^[a-z][a-z0-9]*:/.test(path))
        return "";
    return "image://musicart/" + encodeURIComponent(album || "") + "/" + encodeURIComponent(path);
}

/*
 * A streamed track's cover at about px pixels, where its service serves
 * covers at other sizes by URL: the thumbnail a search gives (Spotify's
 * 64 px, SoundCloud's 100, Qobuz's 230, Deezer's 250, Tidal's 320) is
 * blurred and blocky shown large. Other URLs as they are.
 */
function sized(url, px) {
    url = String(url || "");
    if (px <= 320 || url === "")
        return url;
    var m;
    // Spotify: the size is in the image id - 4851 64 px, 1e02 300, b273 640.
    if ((m = /^(https:\/\/i\.scdn\.co\/image\/ab67616d0000)(?:4851|1e02)([0-9a-f]+)$/.exec(url)))
        return m[1] + "b273" + m[2];
    // Tidal: 80, 160, 320, 640, 1280.
    if ((m = /^(https:\/\/resources\.tidal\.com\/images\/.+\/)\d+x\d+\.jpg$/.exec(url)))
        return m[1] + (px > 640 ? "1280x1280" : "640x640") + ".jpg";
    // Deezer: any size, up to 1000 or so.
    if ((m = /^(https:\/\/cdn-images\.dzcdn\.net\/images\/[a-z]+\/[0-9a-f]+\/)\d+x\d+(-.*\.jpg)$/.exec(url)))
        return m[1] + "1000x1000" + m[2];
    // Qobuz: 50, 230, 600 and max.
    if ((m = /^(https:\/\/static\.qobuz\.com\/images\/covers\/.+_)(?:50|230|300)(\.jpg)$/.exec(url)))
        return m[1] + "600" + m[2];
    // SoundCloud: large is 100 px, t500x500 500.
    if ((m = /^(https:\/\/i\d*\.sndcdn\.com\/.+-)(?:large|t300x300|crop)(\.(?:jpg|png))$/.exec(url)))
        return m[1] + "t500x500" + m[2];
    return url;
}
