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

#include <gtest/gtest.h>

#include "artwork.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>
#include <QtCore/QUrl>
#include <QtGui/QImage>

namespace {

const QString fixtures = QStringLiteral(FIXTURES_DIR);

QString redSong(int n)
{
    return fixtures + QStringLiteral("/Ana Ray/Red Sky/0%1 Red Song %1.mp3").arg(n);
}

// The id QQuickPixmap hands an image provider for a URL (qquickpixmapcache.cpp).
QString providerId(const QString &url)
{
    return QUrl(url).toString(QUrl::RemoveScheme | QUrl::RemoveAuthority).mid(1);
}

// QML's encodeURIComponent.
QString encodeURIComponent(const QString &s)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(s, "!'()*-._~"));
}

class ArtworkTest : public ::testing::Test
{
protected:
    void SetUp() override { ASSERT_TRUE(m_cache.isValid()); }

    QTemporaryDir m_cache;
};

} // namespace

TEST(ArtworkKeys, OneEntryPerAlbumFolder)
{
    EXPECT_EQ(ArtworkStore::keyFor(redSong(1), QStringLiteral("Red Sky")),
              ArtworkStore::keyFor(redSong(2), QStringLiteral("red sky ")));
    EXPECT_NE(ArtworkStore::keyFor(QStringLiteral("/a/1.mp3"), QStringLiteral("X")),
              ArtworkStore::keyFor(QStringLiteral("/b/1.mp3"), QStringLiteral("X")));
    EXPECT_NE(ArtworkStore::keyFor(QStringLiteral("/a/1.mp3"), QStringLiteral("X")),
              ArtworkStore::keyFor(QStringLiteral("/a/1.mp3"), QStringLiteral("Y")));
    // No album name: each track on its own.
    EXPECT_NE(ArtworkStore::keyFor(QStringLiteral("/a/1.mp3"), QString()),
              ArtworkStore::keyFor(QStringLiteral("/a/2.mp3"), QString()));
}

TEST(ArtworkKeys, Buckets)
{
    EXPECT_EQ(ArtworkStore::bucket(0), 384);
    EXPECT_EQ(ArtworkStore::bucket(40), 96);
    EXPECT_EQ(ArtworkStore::bucket(96), 96);
    EXPECT_EQ(ArtworkStore::bucket(97), 192);
    EXPECT_EQ(ArtworkStore::bucket(5000), 768);
}

TEST(ArtworkKeys, ProviderIdRoundTrip)
{
    const QStringList albums = {QStringLiteral("AC/DC"), QStringLiteral("100% Hits"), QString(), QStringLiteral("Café ?#")};
    const QStringList paths = {QStringLiteral("/m/a b#1?.mp3"), QStringLiteral("/m/100%/x.flac"),
                               QStringLiteral("/m/été/café.ogg")};
    for (const QString &album : albums) {
        for (const QString &path : paths) {
            const QString url = QStringLiteral("image://musicart/") + encodeURIComponent(album)
                                + QLatin1Char('/') + encodeURIComponent(path);
            QString gotPath, gotAlbum;
            ASSERT_TRUE(ArtworkStore::parseId(providerId(url), &gotPath, &gotAlbum)) << qPrintable(url);
            EXPECT_EQ(gotPath, path);
            EXPECT_EQ(gotAlbum, album);
        }
    }
    QString p, a;
    EXPECT_FALSE(ArtworkStore::parseId(QStringLiteral("nosep"), &p, &a));
    EXPECT_FALSE(ArtworkStore::parseId(QStringLiteral("album/relative.mp3"), &p, &a));
}

TEST_F(ArtworkTest, EmbeddedCover)
{
    ArtworkStore store(m_cache.path());
    const QImage image = store.load(redSong(1), QStringLiteral("Red Sky"), 90);
    ASSERT_FALSE(image.isNull());
    EXPECT_EQ(image.width(), 96);
    EXPECT_EQ(image.height(), 96);
    // Cached once for the album, at that size.
    const QString entry = m_cache.filePath(ArtworkStore::keyFor(redSong(1), QStringLiteral("Red Sky")) + QStringLiteral("-96.jpg"));
    EXPECT_TRUE(QFileInfo::exists(entry));
    EXPECT_FALSE(store.load(redSong(3), QStringLiteral("Red Sky"), 96).isNull());
    // Never larger than the picture itself (300 px).
    EXPECT_EQ(store.load(redSong(1), QStringLiteral("Red Sky"), 700).width(), 300);
}

TEST_F(ArtworkTest, NotAFileHasNoCover)
{
    // A streamed track's path, and a relative one: never looked up in the
    // working directory (which may hold a cover.jpg).
    QTemporaryDir cwd;
    QImage cover(20, 20, QImage::Format_RGB32);
    cover.fill(Qt::red);
    ASSERT_TRUE(cover.save(cwd.filePath(QStringLiteral("cover.jpg"))));
    const QString before = QDir::currentPath();
    ASSERT_TRUE(QDir::setCurrent(cwd.path()));
    ArtworkStore store(m_cache.path());
    EXPECT_TRUE(store.load(QStringLiteral("youtube:abc"), QStringLiteral("X"), 96).isNull());
    EXPECT_TRUE(store.load(QStringLiteral("song.mp3"), QString(), 96).isNull());
    EXPECT_FALSE(store.accent(QStringLiteral("spotify:track:1"), QString()).isValid());
    QDir::setCurrent(before);
}

TEST_F(ArtworkTest, FolderCoverAboveDiscFolder)
{
    ArtworkStore store(m_cache.path());
    const QImage image = store.load(fixtures + QStringLiteral("/Blue Band/Deep Water/CD2/01 Deep 2-1.flac"),
                                    QStringLiteral("Deep Water"), 192);
    ASSERT_FALSE(image.isNull());
    EXPECT_EQ(image.width(), 192);
}

TEST_F(ArtworkTest, NoCoverLeavesMarker)
{
    ArtworkStore store(m_cache.path());
    const QString track = fixtures + QStringLiteral("/Various/Summer Mix/01 Ana Ray - Sun.ogg");
    EXPECT_TRUE(store.load(track, QStringLiteral("Summer Mix"), 96).isNull());
    EXPECT_TRUE(QFileInfo::exists(m_cache.filePath(ArtworkStore::keyFor(track, QStringLiteral("Summer Mix")) + QStringLiteral(".none"))));
    EXPECT_TRUE(store.load(track, QStringLiteral("Summer Mix"), 96).isNull());
    EXPECT_FALSE(store.accent(track, QStringLiteral("Summer Mix")).isValid());
    store.clear();
    EXPECT_TRUE(QDir(m_cache.path()).entryList(QDir::Files).isEmpty());
}

TEST_F(ArtworkTest, NewCoverBesideTrackIsFoundAfterRetag)
{
    QTemporaryDir music;
    const QString track = music.filePath(QStringLiteral("song.ogg"));
    ASSERT_TRUE(QFile::copy(fixtures + QStringLiteral("/Various/Summer Mix/03 Zed - Sun.ogg"), track));
    ArtworkStore store(m_cache.path());
    EXPECT_TRUE(store.load(track, QStringLiteral("A"), 96).isNull());
    // A cover copied in and the track re-tagged (newer than the marker).
    QImage cover(50, 50, QImage::Format_RGB32);
    cover.fill(Qt::green);
    ASSERT_TRUE(cover.save(music.filePath(QStringLiteral("cover.jpg"))));
    QFile f(track);
    ASSERT_TRUE(f.open(QIODevice::ReadWrite));
    ASSERT_TRUE(f.setFileTime(QDateTime::currentDateTime().addSecs(60), QFileDevice::FileModificationTime));
    f.close();
    const QImage found = store.load(track, QStringLiteral("A"), 96);
    ASSERT_FALSE(found.isNull());
    EXPECT_EQ(found.width(), 50);
}

TEST(ArtworkAccent, PicksTheColour)
{
    QImage red(40, 40, QImage::Format_RGB32);
    red.fill(QColor(200, 30, 30));
    const QColor a = ArtworkStore::accentOf(red);
    ASSERT_TRUE(a.isValid());
    EXPECT_LT(a.hsvHue(), 15);
    EXPECT_GE(a.valueF(), 0.55f);

    // Mostly grey with a blue corner: blue.
    QImage mixed(40, 40, QImage::Format_RGB32);
    mixed.fill(QColor(128, 128, 128));
    for (int y = 0; y < 20; ++y)
        for (int x = 0; x < 20; ++x)
            mixed.setPixelColor(x, y, QColor(20, 60, 220));
    const QColor b = ArtworkStore::accentOf(mixed);
    EXPECT_NEAR(b.hsvHue(), 225, 20);

    // Grey stays grey, but bright enough for the dark player.
    QImage grey(40, 40, QImage::Format_RGB32);
    grey.fill(QColor(30, 30, 30));
    const QColor g = ArtworkStore::accentOf(grey);
    EXPECT_LT(g.hsvSaturationF(), 0.05f);
    // 0.55, give or take QColor's 16-bit rounding.
    EXPECT_GE(g.valueF(), 0.549f);

    EXPECT_FALSE(ArtworkStore::accentOf(QImage()).isValid());
}
