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

#include "artprovider.h"

#include <QtCore/QCoreApplication>
#include <QtCore/QPointer>
#include <QtCore/QRunnable>
#include <QtCore/QStandardPaths>
#include <QtCore/QThreadPool>

namespace {

QString defaultCacheDir()
{
    // MUSIC_ART_CACHE: the tests' throwaway directory.
    QString overridden = qEnvironmentVariable("MUSIC_ART_CACHE");
    if (!overridden.isEmpty())
        return overridden;
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
            + QLatin1String("/org.webosports.app.music/art");
}

QImage noCover()
{
    QImage image(1, 1, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    return image;
}

class ArtResponse : public QQuickImageResponse, public QRunnable
{
public:
    ArtResponse(const QString &id, int size)
        : m_id(id)
        , m_size(size)
    {
        setAutoDelete(false);
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    void run() override
    {
        QString path;
        QString album;
        if (ArtworkStore::parseId(m_id, &path, &album))
            m_image = ArtProvider::store().load(path, album, m_size);
        if (m_image.isNull())
            m_image = noCover();
        Q_EMIT finished();
    }

private:
    QString m_id;
    int m_size;
    QImage m_image;
};

} // namespace

ArtProvider::ArtProvider() = default;

ArtworkStore &ArtProvider::store()
{
    static ArtworkStore instance(defaultCacheDir());
    return instance;
}

QThreadPool *ArtProvider::pool()
{
    static QThreadPool *instance = []() {
        auto *p = new QThreadPool;
        p->setMaxThreadCount(2);
        return p;
    }();
    return instance;
}

QQuickImageResponse *ArtProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    const int size = qMax(requestedSize.width(), requestedSize.height());
    auto *response = new ArtResponse(id, size);
    pool()->start(response);
    return response;
}

ArtAccent::ArtAccent(QObject *parent)
    : QObject(parent)
{
}

void ArtAccent::setPath(const QString &path)
{
    if (m_path == path)
        return;
    m_path = path;
    Q_EMIT pathChanged();
    refresh();
}

void ArtAccent::setAlbum(const QString &album)
{
    if (m_album == album)
        return;
    m_album = album;
    Q_EMIT albumChanged();
    refresh();
}

void ArtAccent::refresh()
{
    const int generation = ++m_generation;
    if (m_path.isEmpty()) {
        setColor(QColor(), generation);
        return;
    }
    // Made and read only on the GUI thread; the worker just carries it back.
    const QPointer<ArtAccent> guard(this);
    const QString trackPath = m_path;
    const QString albumName = m_album;
    ArtProvider::pool()->start([guard, trackPath, albumName, generation]() {
        const QColor color = ArtProvider::store().accent(trackPath, albumName);
        QMetaObject::invokeMethod(QCoreApplication::instance(), [guard, color, generation]() {
            if (guard)
                guard->setColor(color, generation);
        }, Qt::QueuedConnection);
    });
}

void ArtAccent::setColor(const QColor &color, int generation)
{
    // An answer for a track that is no longer the one asked about.
    if (generation != m_generation || color == m_color)
        return;
    m_color = color;
    Q_EMIT colorChanged();
}

ArtCache::ArtCache(QObject *parent)
    : QObject(parent)
{
}

QString ArtCache::directory() const
{
    return ArtProvider::store().cacheDir();
}

void ArtCache::clear()
{
    ArtProvider::store().clear();
}
