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

#ifndef ARTPROVIDER_H
#define ARTPROVIDER_H

#include "artwork.h"

#include <QtCore/QObject>
#include <QtGui/QColor>
#include <QtQuick/QQuickImageProvider>

class QThreadPool;

/*
 * image://musicart/<album>/<path>, both percent-encoded (see
 * qml/js/Art.js): the track's cover, found and scaled off the GUI thread.
 *
 * A track without a cover gives a 1x1 transparent image rather than an
 * error, so lists do not log a warning for every such row; an Image shows
 * its placeholder while implicitWidth <= 1.
 */
class ArtProvider : public QQuickAsyncImageProvider
{
public:
    ArtProvider();

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

    /// The store every cover goes through: the provider, ArtAccent and
    /// ArtCache share it.
    static ArtworkStore &store();
    /// Two threads: covers keep coming while one large one is decoded, and
    /// the slow devices have no more cores to give.
    static QThreadPool *pool();
};

/*
 * The colour of the cover of the playing track, to tint the player with.
 *
 *     ArtAccent { id: accent; path: player.current.path; album: player.current.album }
 *     color: accent.hasArt ? accent.color : theme.accent
 */
class ArtAccent : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString album READ album WRITE setAlbum NOTIFY albumChanged)
    Q_PROPERTY(QColor color READ color NOTIFY colorChanged)
    Q_PROPERTY(bool hasArt READ hasArt NOTIFY colorChanged)

public:
    explicit ArtAccent(QObject *parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString &path);
    QString album() const { return m_album; }
    void setAlbum(const QString &album);
    QColor color() const { return m_color; }
    bool hasArt() const { return m_color.isValid(); }

Q_SIGNALS:
    void pathChanged();
    void albumChanged();
    void colorChanged();

private:
    void refresh();
    void setColor(const QColor &color, int generation);

    QString m_path;
    QString m_album;
    QColor m_color;
    int m_generation = 0;
};

/// The cover cache as a whole, for Preferences.
class ArtCache : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString directory READ directory CONSTANT)

public:
    explicit ArtCache(QObject *parent = nullptr);

    QString directory() const;
    Q_INVOKABLE void clear();
};

#endif // ARTPROVIDER_H
