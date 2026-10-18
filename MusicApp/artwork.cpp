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

#include "artwork.h"
#include "tags.h"

#include <QtCore/QBuffer>
#include <QtCore/QCryptographicHash>
#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFileInfo>
#include <QtCore/QSaveFile>
#include <QtCore/QUrl>
#include <QtGui/QImageReader>
#include <QtGui/QPainter>

#include <algorithm>
#include <array>

namespace {

constexpr std::array<int, 4> buckets = {96, 192, 384, 768};
// A track found to have no cover is looked at again after this long, in
// case a cover.jpg has been copied in beside it since.
constexpr qint64 markerLifetimeSecs = qint64(7) * 24 * 3600;

QImage readScaled(QImageReader &reader, int size)
{
    reader.setAutoTransform(true);
    const QSize full = reader.size();
    if (full.isValid() && (full.width() > size || full.height() > size))
        reader.setScaledSize(full.scaled(size, size, Qt::KeepAspectRatio));
    QImage image = reader.read();
    if (!image.isNull() && (image.width() > size || image.height() > size))
        image = image.scaled(size, size, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return image;
}

} // namespace

ArtworkStore::ArtworkStore(const QString &cacheDir)
    : m_cacheDir(cacheDir)
{
    QDir().mkpath(m_cacheDir);
}

QString ArtworkStore::keyFor(const QString &path, const QString &album)
{
    const QFileInfo info(path);
    const QString source = album.trimmed().isEmpty()
            ? path
            : info.absolutePath() + QChar(0x1f) + album.trimmed().toCaseFolded();
    return QString::fromLatin1(QCryptographicHash::hash(source.toUtf8(), QCryptographicHash::Sha1).toHex());
}

int ArtworkStore::bucket(int size)
{
    if (size <= 0)
        return buckets[2];
    const auto it = std::find_if(buckets.begin(), buckets.end(), [size](int b) { return size <= b; });
    return it != buckets.end() ? *it : buckets.back();
}

QString ArtworkStore::entryPath(const QString &key, int size) const
{
    return m_cacheDir + QLatin1Char('/') + key + QLatin1Char('-') + QString::number(size) + QLatin1String(".jpg");
}

QString ArtworkStore::markerPath(const QString &key) const
{
    return m_cacheDir + QLatin1Char('/') + key + QLatin1String(".none");
}

bool ArtworkStore::isFresh(const QString &cached, const QString &sourcePath)
{
    const QFileInfo entry(cached);
    if (!entry.exists())
        return false;
    // A track that was re-tagged (a new embedded cover) is newer than its entry.
    const QFileInfo source(sourcePath);
    return !source.exists() || entry.lastModified() >= source.lastModified();
}

QImage ArtworkStore::decodeSource(const QString &path, int size)
{
    QByteArray embedded = Tags::embeddedCover(path);
    if (!embedded.isEmpty()) {
        QBuffer buffer(&embedded);
        buffer.open(QIODevice::ReadOnly);
        QImageReader reader(&buffer);
        const QImage image = readScaled(reader, size);
        if (!image.isNull())
            return image;
    }
    const QFileInfo track(path);
    QString cover = Tags::folderCover(track.absolutePath());
    // CD1/CD2 folders: the set's cover sits beside them.
    if (cover.isEmpty() && Tags::isDiscFolder(track.dir().dirName())) {
        QDir parent = track.dir();
        if (parent.cdUp())
            cover = Tags::folderCover(parent.absolutePath());
    }
    if (!cover.isEmpty()) {
        QImageReader reader(cover);
        return readScaled(reader, size);
    }
    return QImage();
}

QImage ArtworkStore::load(const QString &path, const QString &album, int size) const
{
    // Files only: a streamed track ("youtube:...") has none, and as a
    // relative path its folder would be the working directory.
    if (path.isEmpty() || !QDir::isAbsolutePath(path))
        return QImage();
    const QString key = keyFor(path, album);
    const int stored = bucket(size);
    const QString entry = entryPath(key, stored);

    if (isFresh(entry, path)) {
        QImage cached(entry);
        if (!cached.isNull())
            return cached;
    }
    const QString marker = markerPath(key);
    if (isFresh(marker, path)
        && QFileInfo(marker).lastModified().secsTo(QDateTime::currentDateTime()) < markerLifetimeSecs)
        return QImage();

    QImage image = decodeSource(path, stored);
    if (image.isNull()) {
        QSaveFile none(marker);
        if (none.open(QIODevice::WriteOnly))
            none.commit();
        return image;
    }
    QFile::remove(marker);
    // A cover with transparency would turn black as JPEG; flatten it on white.
    QImage flat(image.size(), QImage::Format_RGB32);
    flat.fill(Qt::white);
    {
        QPainter painter(&flat);
        painter.drawImage(0, 0, image);
    }
    QSaveFile file(entry);
    if (file.open(QIODevice::WriteOnly) && flat.save(&file, "JPG", 88))
        file.commit();
    return flat;
}

QColor ArtworkStore::accent(const QString &path, const QString &album) const
{
    const QImage image = load(path, album, buckets[0]);
    return image.isNull() ? QColor() : accentOf(image);
}

QColor ArtworkStore::accentOf(const QImage &image)
{
    if (image.isNull())
        return QColor();
    const QImage small = image.scaled(48, 48, Qt::IgnoreAspectRatio, Qt::FastTransformation)
                                 .convertToFormat(QImage::Format_RGB32);

    constexpr int bins = 12;
    std::array<double, bins> weight{};
    std::array<double, bins> r{}, g{}, b{};
    double allR = 0, allG = 0, allB = 0;
    int count = 0;
    for (int y = 0; y < small.height(); ++y) {
        for (int x = 0; x < small.width(); ++x) {
            const QColor c(small.pixel(x, y));
            allR += c.redF();
            allG += c.greenF();
            allB += c.blueF();
            ++count;
            const float s = c.hsvSaturationF();
            const float v = c.valueF();
            if (s < 0.25f || v < 0.2f || c.hsvHue() < 0)
                continue;
            const int bin = qBound(0, c.hsvHue() * bins / 360, bins - 1);
            const double w = double(s) * double(v);
            weight[static_cast<size_t>(bin)] += w;
            r[static_cast<size_t>(bin)] += c.redF() * w;
            g[static_cast<size_t>(bin)] += c.greenF() * w;
            b[static_cast<size_t>(bin)] += c.blueF() * w;
        }
    }
    if (count == 0)
        return QColor();

    size_t best = 0;
    double total = 0;
    for (size_t i = 0; i < weight.size(); ++i) {
        total += weight[i];
        if (weight[i] > weight[best])
            best = i;
    }
    QColor picked;
    // A cover that is mostly grey (under a tenth of it coloured) gets its
    // average, and is left grey.
    if (total < count * 0.05 || weight[best] <= 0) {
        picked = QColor::fromRgbF(float(allR / count), float(allG / count), float(allB / count));
    } else {
        picked = QColor::fromRgbF(float(r[best] / weight[best]), float(g[best] / weight[best]),
                                  float(b[best] / weight[best]));
    }
    // Bright enough to read against the player's dark background, and not
    // so saturated that it glares.
    float h, s, v;
    picked.getHsvF(&h, &s, &v);
    return QColor::fromHsvF(h, qMin(s, 0.85f), qBound(0.55f, v, 0.92f));
}

bool ArtworkStore::parseId(const QString &id, QString *path, QString *album)
{
    const qsizetype slash = id.indexOf(QLatin1Char('/'));
    if (slash < 0)
        return false;
    *album = QUrl::fromPercentEncoding(id.left(slash).toUtf8());
    *path = QUrl::fromPercentEncoding(id.mid(slash + 1).toUtf8());
    return path->startsWith(QLatin1Char('/'));
}

void ArtworkStore::clear()
{
    QDir dir(m_cacheDir);
    const QStringList entries = dir.entryList({QStringLiteral("*.jpg"), QStringLiteral("*.none")}, QDir::Files);
    for (const QString &entry : entries)
        dir.remove(entry);
}
