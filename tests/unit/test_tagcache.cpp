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

#include "tagcache.h"

#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>
#include <QtTest/QSignalSpy>

namespace {

const QString fixtures = QStringLiteral(FIXTURES_DIR);

QVariantList collect(TagReader &reader, const QVariantList &songs)
{
    QVariantList all;
    QObject::connect(&reader, &TagReader::enriched, [&all](const QVariantList &batch) { all += batch; });
    QSignalSpy done(&reader, &TagReader::finished);
    reader.enrich(songs);
    EXPECT_TRUE(done.wait(10000));
    QObject::disconnect(&reader, &TagReader::enriched, nullptr, nullptr);
    return all;
}

QVariantMap song(const QString &rel, double modified)
{
    return QVariantMap{{QStringLiteral("path"), fixtures + rel}, {QStringLiteral("modified"), modified}};
}

} // namespace

TEST(TagIndex, SaveLoadLookup)
{
    QTemporaryDir dir;
    const QString file = dir.filePath(QStringLiteral("sub/tags.json"));
    TagIndex index(file);
    EXPECT_FALSE(index.load());
    index.insert(QStringLiteral("/a.mp3"), 10, QVariantMap{{QStringLiteral("duration"), 1234}});
    index.insert(QStringLiteral("/b.mp3"), 20, QVariantMap());
    ASSERT_TRUE(index.save());

    TagIndex again(file);
    ASSERT_TRUE(again.load());
    EXPECT_EQ(again.size(), 2);
    QVariantMap fields;
    ASSERT_TRUE(again.lookup(QStringLiteral("/a.mp3"), 10, &fields));
    EXPECT_EQ(fields.value(QStringLiteral("duration")).toInt(), 1234);
    // Modified since: read again.
    EXPECT_FALSE(again.lookup(QStringLiteral("/a.mp3"), 11, &fields));
    EXPECT_FALSE(again.lookup(QStringLiteral("/c.mp3"), 10, &fields));
    EXPECT_EQ(again.prune(QSet<QString>{QStringLiteral("/b.mp3")}), 1);
    EXPECT_EQ(again.size(), 1);
}

TEST(TagIndex, OtherVersionIsIgnored)
{
    QTemporaryDir dir;
    const QString file = dir.filePath(QStringLiteral("tags.json"));
    QFile f(file);
    ASSERT_TRUE(f.open(QIODevice::WriteOnly));
    f.write("{\"version\": 99, \"entries\": {\"/a\": {\"m\": 1, \"f\": {}}}}");
    f.close();
    TagIndex index(file);
    EXPECT_FALSE(index.load());
    EXPECT_EQ(index.size(), 0);
}

TEST(TagIndex, CachedFieldsLeaveOutNothingValues)
{
    const QVariantMap all{{QStringLiteral("duration"), 3000}, {QStringLiteral("year"), 0},
                          {QStringLiteral("composer"), QString()}, {QStringLiteral("trackGain"), -1.5},
                          {QStringLiteral("title"), QStringLiteral("not cached")}, {QStringLiteral("albumArtist"), QStringLiteral("X")}};
    const QVariantMap cached = TagIndex::cachedFields(all);
    EXPECT_EQ(cached.size(), 3);
    EXPECT_TRUE(cached.contains(QStringLiteral("duration")));
    EXPECT_TRUE(cached.contains(QStringLiteral("trackGain")));
    EXPECT_TRUE(cached.contains(QStringLiteral("albumArtist")));
}

TEST(TagReader, EnrichAndCache)
{
    QTemporaryDir dir;
    TagReader reader;
    reader.setCacheFile(dir.filePath(QStringLiteral("tags.json")));
    const QVariantList songs{song(QStringLiteral("/Ana Ray/Red Sky/02 Red Song 2.mp3"), 5),
                             song(QStringLiteral("/Blue Band/Deep Water/CD1/01 Deep 1-1.flac"), 6),
                             song(QStringLiteral("/missing.mp3"), 7)};
    const QVariantList first = collect(reader, songs);
    ASSERT_EQ(first.size(), 3);
    EXPECT_FALSE(reader.busy());
    QVariantMap red;
    for (const QVariant &v : first) {
        if (v.toMap().value(QStringLiteral("path")).toString().endsWith(QStringLiteral("Red Song 2.mp3")))
            red = v.toMap();
    }
    EXPECT_NEAR(red.value(QStringLiteral("duration")).toInt(), 3000, 150);
    EXPECT_EQ(red.value(QStringLiteral("year")).toInt(), 2019);
    EXPECT_DOUBLE_EQ(red.value(QStringLiteral("trackGain")).toDouble(), -2.5);
    EXPECT_TRUE(QFileInfo::exists(dir.filePath(QStringLiteral("tags.json"))));
    int missing = 0;
    for (const QVariant &v : first) {
        if (v.toMap().value(QStringLiteral("missing")).toBool()) {
            ++missing;
            EXPECT_TRUE(v.toMap().value(QStringLiteral("path")).toString().endsWith(QStringLiteral("/missing.mp3")));
        }
    }
    EXPECT_EQ(missing, 1);

    // The second time comes from the file: same answers. The missing file
    // is not cached.
    TagIndex index(dir.filePath(QStringLiteral("tags.json")));
    ASSERT_TRUE(index.load());
    EXPECT_EQ(index.size(), 2);
    TagReader second;
    second.setCacheFile(dir.filePath(QStringLiteral("tags.json")));
    const QVariantList again = collect(second, songs);
    EXPECT_EQ(again.size(), 3);
}

TEST(TagReader, FileGoneSinceCachedIsMissing)
{
    QTemporaryDir dir;
    const QString copy = dir.filePath(QStringLiteral("song.mp3"));
    ASSERT_TRUE(QFile::copy(fixtures + QStringLiteral("/Ana Ray/Red Sky/02 Red Song 2.mp3"), copy));
    const QVariantList songs{QVariantMap{{QStringLiteral("path"), copy}, {QStringLiteral("modified"), 5.0}}};
    TagReader reader;
    reader.setCacheFile(dir.filePath(QStringLiteral("tags.json")));
    const QVariantList first = collect(reader, songs);
    ASSERT_EQ(first.size(), 1);
    EXPECT_FALSE(first.at(0).toMap().value(QStringLiteral("missing")).toBool());

    // Removed; the indexer still has it, the cache too.
    ASSERT_TRUE(QFile::remove(copy));
    const QVariantList second = collect(reader, songs);
    ASSERT_EQ(second.size(), 1);
    EXPECT_TRUE(second.at(0).toMap().value(QStringLiteral("missing")).toBool());
    TagIndex index(dir.filePath(QStringLiteral("tags.json")));
    ASSERT_TRUE(index.load());
    EXPECT_EQ(index.size(), 0);
}

TEST(TagReader, CancelStopsReporting)
{
    TagReader reader;
    QSignalSpy batches(&reader, &TagReader::enriched);
    QSignalSpy done(&reader, &TagReader::finished);
    reader.enrich(QVariantList{song(QStringLiteral("/Ana Ray/Red Sky/01 Red Song 1.mp3"), 1)});
    reader.cancel();
    EXPECT_FALSE(reader.busy());
    EXPECT_FALSE(done.wait(1500));
    EXPECT_EQ(batches.count(), 0);
}

TEST(TagReader, ReadOneWithLyrics)
{
    TagReader reader;
    const QVariantMap info = reader.read(fixtures + QStringLiteral("/Ana Ray/Red Sky/01 Red Song 1.mp3"));
    EXPECT_EQ(info.value(QStringLiteral("format")).toString(), QStringLiteral("MP3"));
    EXPECT_GT(info.value(QStringLiteral("size")).toDouble(), 1000);
    EXPECT_TRUE(info.value(QStringLiteral("lyrics")).toString().contains(QStringLiteral("Chorus line")));
    EXPECT_FALSE(reader.read(fixtures + QStringLiteral("/Ana Ray/Red Sky/02 Red Song 2.mp3")).contains(QStringLiteral("lyrics")));
}
