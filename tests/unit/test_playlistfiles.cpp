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

#include "playlistfiles.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>

namespace {

bool writeFile(const QString &path, const QByteArray &content)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write(content) == content.size();
}

QByteArray readFile(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

} // namespace

TEST(PlaylistParse, M3uEntries)
{
    const QByteArray m3u = "\xEF\xBB\xBF#EXTM3U\r\n#EXTINF:3,A - B\r\nsub/a.mp3\r\n/abs/b.flac\r\n"
                           "file:///url/c%20d.ogg\r\nhttp://radio/stream\r\nWin\\Path\\e.mp3\r\n"
                           "C:\\Music\\f.mp3\r\n../up/g.mp3\r\n\r\n";
    const QStringList tracks = PlaylistFiles::parse(m3u, QStringLiteral("/lists"));
    EXPECT_EQ(tracks, (QStringList{QStringLiteral("/lists/sub/a.mp3"), QStringLiteral("/abs/b.flac"),
                                   QStringLiteral("/url/c d.ogg"), QStringLiteral("/lists/Win/Path/e.mp3"),
                                   QStringLiteral("/lists/Music/f.mp3"), QStringLiteral("/up/g.mp3")}));
}

TEST(PlaylistParse, Pls)
{
    const QByteArray pls = "[playlist]\nFile1=a.mp3\nTitle1=A\nFile2 = /b.mp3\nNumberOfEntries=2\n";
    EXPECT_EQ(PlaylistFiles::parse(pls, QStringLiteral("/p")), (QStringList{QStringLiteral("/p/a.mp3"), QStringLiteral("/b.mp3")}));
}

TEST(PlaylistParse, Latin1Fallback)
{
    const QByteArray latin1 = "caf\xe9.mp3\n";
    EXPECT_EQ(PlaylistFiles::parse(latin1, QStringLiteral("/p")), QStringList{QString::fromUtf8("/p/caf\xc3\xa9.mp3")});
    const QByteArray utf8 = "caf\xc3\xa9.mp3\n";
    EXPECT_EQ(PlaylistFiles::parse(utf8, QStringLiteral("/p")), QStringList{QString::fromUtf8("/p/caf\xc3\xa9.mp3")});
}

TEST(PlaylistWrite, M3u8RelativeWhereItCan)
{
    const QVariantList tracks{
        QVariantMap{{QStringLiteral("path"), QStringLiteral("/m/Lists/../A/x.mp3")}, {QStringLiteral("title"), QStringLiteral("X")},
                    {QStringLiteral("artist"), QStringLiteral("Y")}, {QStringLiteral("duration"), 61500}},
        QVariantMap{{QStringLiteral("path"), QStringLiteral("/other/z.ogg")}},
        QVariantMap{{QStringLiteral("title"), QStringLiteral("no path")}},
    };
    const QByteArray out = PlaylistFiles::writeM3u8(tracks, QStringLiteral("/m"));
    EXPECT_EQ(out, QByteArray("#EXTM3U\n#EXTINF:61,Y - X\nA/x.mp3\n#EXTINF:-1,z\n/other/z.ogg\n"));
    // And it reads back to the same files.
    EXPECT_EQ(PlaylistFiles::parse(out, QStringLiteral("/m")),
              (QStringList{QStringLiteral("/m/A/x.mp3"), QStringLiteral("/other/z.ogg")}));
}

TEST(PlaylistWrite, SafeFileName)
{
    EXPECT_EQ(PlaylistFiles::safeFileName(QStringLiteral("Rock/Pop: \"best\"")), QStringLiteral("Rock_Pop_ _best_"));
    EXPECT_EQ(PlaylistFiles::safeFileName(QStringLiteral("..hidden")), QStringLiteral("hidden"));
    EXPECT_EQ(PlaylistFiles::safeFileName(QStringLiteral("   ")), QStringLiteral("Playlist"));
    EXPECT_EQ(PlaylistFiles::safeFileName(QString(200, QLatin1Char('a'))).size(), 120);
}

TEST(PlaylistIO, ReadKeepsExistingTracks)
{
    QTemporaryDir dir;
    ASSERT_TRUE(writeFile(dir.filePath(QStringLiteral("A/x.mp3")), "x"));
    ASSERT_TRUE(writeFile(dir.filePath(QStringLiteral("list.m3u")), "A/x.mp3\nA/gone.mp3\n"));
    PlaylistIO io;
    EXPECT_EQ(io.read(dir.filePath(QStringLiteral("list.m3u"))), QStringList{dir.filePath(QStringLiteral("A/x.mp3"))});
    EXPECT_TRUE(io.read(dir.filePath(QStringLiteral("A/x.mp3"))).isEmpty());
    EXPECT_TRUE(io.read(dir.filePath(QStringLiteral("none.m3u"))).isEmpty());
    EXPECT_TRUE(PlaylistIO::isPlaylistFile(QStringLiteral("a.M3U8")));
    EXPECT_FALSE(PlaylistIO::isPlaylistFile(QStringLiteral("a.mp3")));
}

TEST(PlaylistIO, WriteConfinedToExportDir)
{
    QTemporaryDir dir;
    PlaylistIO io;
    EXPECT_TRUE(io.write(QStringLiteral("x"), QVariantList()).isEmpty());
    io.setExportDir(dir.filePath(QStringLiteral("Playlists")));
    const QVariantList tracks{QVariantMap{{QStringLiteral("path"), dir.filePath(QStringLiteral("Music/a.mp3"))}}};
    const QString written = io.write(QStringLiteral("../../etc/evil"), tracks);
    ASSERT_FALSE(written.isEmpty());
    EXPECT_EQ(QFileInfo(written).absolutePath(), QFileInfo(dir.filePath(QStringLiteral("Playlists"))).canonicalFilePath());
    EXPECT_TRUE(written.endsWith(QStringLiteral(".._.._etc_evil.m3u8")) || written.endsWith(QStringLiteral("_.._etc_evil.m3u8")));
    EXPECT_TRUE(readFile(written).contains("../Music/a.mp3") || readFile(written).contains(dir.filePath(QStringLiteral("Music/a.mp3")).toUtf8()));
    // Writing again replaces the earlier export.
    EXPECT_EQ(io.write(QStringLiteral("../../etc/evil"), QVariantList()), written);
    EXPECT_EQ(readFile(written), QByteArray("#EXTM3U\n"));
}
