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
