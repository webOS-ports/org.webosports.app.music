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

#ifndef ARTWORK_H
#define ARTWORK_H

#include <QtCore/QString>
#include <QtGui/QColor>
#include <QtGui/QImage>

/*
 * Album covers, found once and kept scaled on disk.
 *
 * The media indexer stores no audio thumbnails, so a cover comes from the
 * track itself (an embedded picture) or from an image beside it
 * (cover.jpg and friends), is scaled to one of a few sizes and written to
 * the cache as JPEG. A track that has none leaves a marker, so its folder
 * is not searched again every time a list scrolls past it.
 *
 * A cover belongs to an album, not a track: the key is the track's folder
 * and album name, so the fifteen tracks of an album share one entry. A
 * track with no album name has its own.
 *
 * Safe to use from several threads at once: every entry is written to a
 * temporary file and renamed into place.
 */
class ArtworkStore
{
public:
    explicit ArtworkStore(const QString &cacheDir);

    QString cacheDir() const { return m_cacheDir; }

    /// The cache key of the cover of the track at path, on album.
    static QString keyFor(const QString &path, const QString &album);

    /// The size a cover is stored at for a request of size pixels: one of a
    /// few, so a list and a grid asking for slightly different sizes share it.
    static int bucket(int size);

    /// The cover, at most size pixels on its longer side (larger requests are
    /// capped at the largest bucket). A null image when the track has none.
    QImage load(const QString &path, const QString &album, int size) const;

    /// A colour to theme the player with, picked from the cover: the most
    /// common strongly coloured hue, or the average when the cover is grey.
    /// Invalid when the track has no cover.
    QColor accent(const QString &path, const QString &album) const;

    /// The accent colour of an image (see accent()).
    static QColor accentOf(const QImage &image);

    /// Splits an image provider id - "<album>/<path>", each percent-encoded
    /// by QML's encodeURIComponent - into its parts. False when malformed.
    static bool parseId(const QString &id, QString *path, QString *album);

    /// Deletes every cached cover.
    void clear();

private:
    static QImage decodeSource(const QString &path, int size);
    QString entryPath(const QString &key, int size) const;
    QString markerPath(const QString &key) const;
    static bool isFresh(const QString &cached, const QString &sourcePath);

    QString m_cacheDir;
};

#endif // ARTWORK_H
