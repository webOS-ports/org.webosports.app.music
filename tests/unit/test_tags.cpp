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

#include "tags.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QTemporaryDir>

namespace {

const QString fixtures = QStringLiteral(FIXTURES_DIR);

bool touch(const QString &path, const QByteArray &content = QByteArray("x"))
{
    QFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write(content) == content.size();
}

} // namespace

TEST(Tags, ParseGain)
{
    double g = 0;
    EXPECT_TRUE(Tags::parseGain(QStringLiteral("-6.53 dB"), &g));
    EXPECT_DOUBLE_EQ(g, -6.53);
    EXPECT_TRUE(Tags::parseGain(QStringLiteral("+1,5 db"), &g));
    EXPECT_DOUBLE_EQ(g, 1.5);
    EXPECT_TRUE(Tags::parseGain(QStringLiteral("0"), &g));
    EXPECT_DOUBLE_EQ(g, 0.0);
    EXPECT_FALSE(Tags::parseGain(QString(), &g));
    EXPECT_FALSE(Tags::parseGain(QStringLiteral("loud"), &g));
    EXPECT_FALSE(Tags::parseGain(QStringLiteral("-99 dB"), &g));
}

TEST(Tags, ParseNumberPair)
{
    int total = 0;
    EXPECT_EQ(Tags::parseNumberPair(QStringLiteral("3/12"), &total), 3);
    EXPECT_EQ(total, 12);
    total = 7;
    EXPECT_EQ(Tags::parseNumberPair(QStringLiteral(" 4 "), &total), 4);
    EXPECT_EQ(total, 7);
    EXPECT_EQ(Tags::parseNumberPair(QStringLiteral("x/y"), &total), 0);
    EXPECT_EQ(Tags::parseNumberPair(QString(), nullptr), 0);
    EXPECT_EQ(Tags::parseNumberPair(QStringLiteral("-2"), nullptr), 0);
}

TEST(Tags, ParseYear)
{
    EXPECT_EQ(Tags::parseYear(QStringLiteral("2009-04-01")), 2009);
    EXPECT_EQ(Tags::parseYear(QStringLiteral("April 1999")), 1999);
    EXPECT_EQ(Tags::parseYear(QStringLiteral("12345")), 0);
    EXPECT_EQ(Tags::parseYear(QString()), 0);
}

TEST(Tags, ReadMp3WithGainAndCover)
{
    const Tags::TrackInfo info = Tags::read(fixtures + QStringLiteral("/Ana Ray/Red Sky/01 Red Song 1.mp3"));
    ASSERT_TRUE(info.valid);
    EXPECT_EQ(info.title, QStringLiteral("Red Song 1"));
    EXPECT_EQ(info.artist, QStringLiteral("Ana Ray"));
    EXPECT_EQ(info.album, QStringLiteral("Red Sky"));
    EXPECT_TRUE(info.albumArtist.isEmpty());
    EXPECT_EQ(info.track, 1);
    EXPECT_EQ(info.trackTotal, 3);
    EXPECT_EQ(info.year, 2019);
    EXPECT_EQ(info.genre, QStringLiteral("Pop"));
    EXPECT_TRUE(info.hasTrackGain);
    EXPECT_DOUBLE_EQ(info.trackGain, -1.5);
    EXPECT_TRUE(info.hasAlbumGain);
    EXPECT_DOUBLE_EQ(info.albumGain, -2.0);
    EXPECT_NEAR(info.durationMs, 3000, 150);
    EXPECT_GT(info.sampleRate, 0);
    EXPECT_FALSE(Tags::embeddedCover(fixtures + QStringLiteral("/Ana Ray/Red Sky/01 Red Song 1.mp3")).isEmpty());
}

TEST(Tags, ReadFlacDisc)
{
    const Tags::TrackInfo info = Tags::read(fixtures + QStringLiteral("/Blue Band/Deep Water/CD2/02 Deep 2-2.flac"));
    ASSERT_TRUE(info.valid);
    EXPECT_EQ(info.disc, 2);
    EXPECT_EQ(info.discTotal, 2);
    EXPECT_EQ(info.track, 2);
    EXPECT_FALSE(info.hasTrackGain);
    EXPECT_TRUE(Tags::embeddedCover(fixtures + QStringLiteral("/Blue Band/Deep Water/CD2/02 Deep 2-2.flac")).isEmpty());
}

TEST(Tags, ReadOggAndVariantMap)
{
    const Tags::TrackInfo info = Tags::read(fixtures + QStringLiteral("/Various/Summer Mix/02 Cool Cats - Sun.ogg"));
    ASSERT_TRUE(info.valid);
    EXPECT_EQ(info.artist, QStringLiteral("Cool Cats"));
    const QVariantMap map = Tags::toVariantMap(info);
    EXPECT_EQ(map.value(QStringLiteral("title")).toString(), QStringLiteral("Sun 2"));
    EXPECT_FALSE(map.contains(QStringLiteral("trackGain")));
    EXPECT_FALSE(map.contains(QStringLiteral("lyrics")));
}

TEST(Tags, UnreadableFile)
{
    QTemporaryDir dir;
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("junk.mp3")), "not audio at all"));
    EXPECT_FALSE(Tags::read(dir.filePath(QStringLiteral("junk.mp3"))).valid);
    EXPECT_FALSE(Tags::read(dir.filePath(QStringLiteral("missing.mp3"))).valid);
    EXPECT_TRUE(Tags::embeddedCover(dir.filePath(QStringLiteral("missing.mp3"))).isEmpty());
}

TEST(Tags, FolderCoverPreference)
{
    QTemporaryDir dir;
    // A single image is the cover.
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("scan.jpg"))));
    EXPECT_EQ(Tags::folderCover(dir.path()), dir.filePath(QStringLiteral("scan.jpg")));
    // Several: none is chosen by guesswork...
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("back.jpg"))));
    EXPECT_TRUE(Tags::folderCover(dir.path()).isEmpty());
    // ...but a name that says so is.
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("AlbumArt_{X}_Large.jpg"))));
    EXPECT_EQ(Tags::folderCover(dir.path()), dir.filePath(QStringLiteral("AlbumArt_{X}_Large.jpg")));
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("Folder.PNG"))));
    EXPECT_EQ(Tags::folderCover(dir.path()), dir.filePath(QStringLiteral("Folder.PNG")));
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("cover.jpg"))));
    EXPECT_EQ(Tags::folderCover(dir.path()), dir.filePath(QStringLiteral("cover.jpg")));
    EXPECT_TRUE(Tags::folderCover(QString()).isEmpty());
    EXPECT_TRUE(Tags::folderCover(dir.filePath(QStringLiteral("nope"))).isEmpty());
}

TEST(Tags, DiscFolders)
{
    EXPECT_TRUE(Tags::isDiscFolder(QStringLiteral("CD1")));
    EXPECT_TRUE(Tags::isDiscFolder(QStringLiteral("Disc 2")));
    EXPECT_TRUE(Tags::isDiscFolder(QStringLiteral("disk_03")));
    EXPECT_TRUE(Tags::isDiscFolder(QStringLiteral("Vol. 2")));
    EXPECT_FALSE(Tags::isDiscFolder(QStringLiteral("Discography")));
    EXPECT_FALSE(Tags::isDiscFolder(QStringLiteral("CD")));
}

TEST(Tags, SidecarLyrics)
{
    QTemporaryDir dir;
    const QString track = dir.filePath(QStringLiteral("Song.mp3"));
    EXPECT_TRUE(Tags::sidecarLyrics(track).isEmpty());
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("Song.txt")), "plain words"));
    EXPECT_EQ(Tags::sidecarLyrics(track), QStringLiteral("plain words"));
    // An .lrc wins, and its byte-order mark goes.
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("Song.lrc")), "\xEF\xBB\xBF[00:01.00]Hi \xC3\xA9"));
    EXPECT_EQ(Tags::sidecarLyrics(track), QString::fromUtf8("[00:01.00]Hi \xC3\xA9"));
    ASSERT_TRUE(touch(dir.filePath(QStringLiteral("Big.lrc")), QByteArray(600 * 1024, 'a')));
    EXPECT_TRUE(Tags::sidecarLyrics(dir.filePath(QStringLiteral("Big.mp3"))).isEmpty());
}

TEST(Tags, AudioExtensions)
{
    EXPECT_TRUE(Tags::isAudioFile(QStringLiteral("/a/b.MP3")));
    EXPECT_TRUE(Tags::isAudioFile(QStringLiteral("x.opus")));
    EXPECT_FALSE(Tags::isAudioFile(QStringLiteral("x.jpg")));
    EXPECT_FALSE(Tags::isAudioFile(QStringLiteral("mp3")));
}
