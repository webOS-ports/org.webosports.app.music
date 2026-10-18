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

#include "filebrowser.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>

namespace {

bool touch(const QString &path)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write("x") == 1;
}

QStringList names(const QVariantList &entries)
{
    QStringList out;
    for (const QVariant &v : entries)
        out << v.toMap().value(QStringLiteral("name")).toString();
    return out;
}

} // namespace

TEST(FileBrowser, ListsFoldersThenMusicNaturally)
{
    QTemporaryDir dir;
    for (const char *f : {"10 ten.mp3", "2 two.flac", "cover.jpg", ".hidden.mp3", "notes.txt", "mix.m3u", "Album/1.mp3", ".cache/x.mp3", "b dir/x"})
        ASSERT_TRUE(touch(dir.filePath(QString::fromLatin1(f))));
    FileBrowser fb;
    const QVariantList entries = fb.list(dir.path());
    EXPECT_EQ(names(entries), (QStringList{QStringLiteral("Album"), QStringLiteral("b dir"), QStringLiteral("2 two.flac"),
                                           QStringLiteral("10 ten.mp3"), QStringLiteral("mix.m3u")}));
    EXPECT_TRUE(entries.at(0).toMap().value(QStringLiteral("isDir")).toBool());
    EXPECT_TRUE(entries.at(4).toMap().value(QStringLiteral("isPlaylist")).toBool());
    EXPECT_FALSE(entries.at(2).toMap().value(QStringLiteral("isPlaylist")).toBool());
    EXPECT_TRUE(fb.list(dir.filePath(QStringLiteral("nope"))).isEmpty());
}

TEST(FileBrowser, AudioFilesUnder)
{
    QTemporaryDir dir;
    for (const char *f : {"A/CD2/1.mp3", "A/CD1/2.mp3", "A/CD1/10.mp3", "A/x.jpg", "B/3.ogg", ".hide/4.mp3"})
        ASSERT_TRUE(touch(dir.filePath(QString::fromLatin1(f))));
    FileBrowser fb;
    const QStringList all = fb.audioFilesUnder(dir.path());
    QStringList rel;
    for (const QString &p : all)
        rel << QDir(dir.path()).relativeFilePath(p);
    EXPECT_EQ(rel, (QStringList{QStringLiteral("A/CD1/2.mp3"), QStringLiteral("A/CD1/10.mp3"), QStringLiteral("A/CD2/1.mp3"),
                                QStringLiteral("B/3.ogg")}));
    EXPECT_EQ(fb.audioFilesUnder(dir.path(), 2).size(), 2);
    EXPECT_TRUE(fb.audioFilesUnder(dir.path(), 0).isEmpty());
    EXPECT_TRUE(fb.audioFilesUnder(dir.filePath(QStringLiteral("A/x.jpg"))).isEmpty());
}

TEST(FileBrowser, RootsLeaveOutSystemAndEmptyMounts)
{
    QTemporaryDir dir;
    const QString media = dir.filePath(QStringLiteral("media"));
    for (const char *f : {"internal/Music/a.mp3", "cryptofs/apps/x", "sdcard/Music/b.mp3", "developer/y"})
        ASSERT_TRUE(touch(media + QLatin1Char('/') + QString::fromLatin1(f)));
    ASSERT_TRUE(QDir().mkpath(media + QStringLiteral("/usb")));
    FileBrowser fb;
    const QVariantList roots = fb.roots(media + QStringLiteral("/internal"), media);
    EXPECT_EQ(names(roots), (QStringList{QStringLiteral("Internal storage"), QStringLiteral("sdcard")}));
}

TEST(FileBrowser, Paths)
{
    FileBrowser fb;
    EXPECT_EQ(fb.folderOf(QStringLiteral("/a/b/c.mp3")), QStringLiteral("/a/b"));
    EXPECT_FALSE(fb.exists(QString()));
    EXPECT_TRUE(fb.exists(QStringLiteral("/")));
}

TEST(StateFile, SaveAndLoad)
{
    QTemporaryDir dir;
    StateFile state;
    EXPECT_FALSE(state.save(QStringLiteral("queue"), QStringLiteral("x")));
    state.setDirectory(dir.filePath(QStringLiteral("data")));
    EXPECT_TRUE(state.save(QStringLiteral("queue"), QString::fromUtf8("{\"a\": \"\xc3\xa9\"}")));
    EXPECT_EQ(state.load(QStringLiteral("queue")), QString::fromUtf8("{\"a\": \"\xc3\xa9\"}"));
    EXPECT_EQ(state.load(QStringLiteral("other")), QString());
    // Names cannot reach out of the folder.
    EXPECT_FALSE(state.save(QStringLiteral("../escape"), QStringLiteral("x")));
    EXPECT_FALSE(state.save(QStringLiteral("Queue"), QStringLiteral("x")));
    EXPECT_FALSE(state.save(QString(), QStringLiteral("x")));
    EXPECT_FALSE(QFileInfo::exists(dir.filePath(QStringLiteral("escape.json"))));
    EXPECT_TRUE(StateFile::isValidName(QStringLiteral("tag-cache2")));
}
