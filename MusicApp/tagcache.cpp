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

#include "tagcache.h"
#include "tags.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QMutexLocker>
#include <QtCore/QSaveFile>

namespace {

// Bumped when the cached fields change, so an older file is read afresh.
constexpr int cacheVersion = 1;
// Results go to QML in batches this big: one signal per file would flood
// the event loop with ten thousand of them on a first run.
constexpr int batchSize = 200;

} // namespace

TagIndex::TagIndex(const QString &file)
    : m_file(file)
{
}

bool TagIndex::load()
{
    m_entries.clear();
    QFile file(m_file);
    if (!file.open(QIODevice::ReadOnly))
        return false;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    const QJsonObject root = doc.object();
    if (root.value(QStringLiteral("version")).toInt() != cacheVersion)
        return false;
    const QJsonObject entries = root.value(QStringLiteral("entries")).toObject();
    m_entries.reserve(entries.size());
    for (auto it = entries.begin(); it != entries.end(); ++it) {
        const QJsonObject e = it.value().toObject();
        Entry entry;
        entry.modified = static_cast<qint64>(e.value(QStringLiteral("m")).toDouble());
        entry.fields = e.value(QStringLiteral("f")).toObject().toVariantMap();
        m_entries.insert(it.key(), entry);
    }
    return true;
}

bool TagIndex::save() const
{
    QJsonObject entries;
    for (auto it = m_entries.constBegin(); it != m_entries.constEnd(); ++it) {
        QJsonObject e;
        e.insert(QStringLiteral("m"), static_cast<double>(it->modified));
        e.insert(QStringLiteral("f"), QJsonObject::fromVariantMap(it->fields));
        entries.insert(it.key(), e);
    }
    QJsonObject root;
    root.insert(QStringLiteral("version"), cacheVersion);
    root.insert(QStringLiteral("entries"), entries);

    QDir().mkpath(QFileInfo(m_file).absolutePath());
    QSaveFile file(m_file);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    return file.commit();
}

bool TagIndex::lookup(const QString &path, qint64 modified, QVariantMap *fields) const
{
    const auto it = m_entries.constFind(path);
    if (it == m_entries.constEnd() || it->modified != modified)
        return false;
    *fields = it->fields;
    return true;
}

void TagIndex::insert(const QString &path, qint64 modified, const QVariantMap &fields)
{
    m_entries.insert(path, Entry{modified, fields});
}

int TagIndex::prune(const QSet<QString> &keep)
{
    int removed = 0;
    for (auto it = m_entries.begin(); it != m_entries.end();) {
        if (!keep.contains(it.key())) {
            it = m_entries.erase(it);
            ++removed;
        } else {
            ++it;
        }
    }
    return removed;
}

QVariantMap TagIndex::cachedFields(const QVariantMap &all)
{
    static const QStringList keys = {
        QStringLiteral("duration"), QStringLiteral("year"), QStringLiteral("composer"),
        QStringLiteral("albumArtist"), QStringLiteral("discTotal"), QStringLiteral("trackGain"),
        QStringLiteral("albumGain"), QStringLiteral("trackPeak"), QStringLiteral("albumPeak"),
    };
    QVariantMap out;
    for (const QString &key : keys) {
        const auto it = all.constFind(key);
        if (it == all.constEnd())
            continue;
        // Empty strings and zeroes say nothing; leaving them out keeps the file small.
        if ((it->typeId() == QMetaType::QString && it->toString().isEmpty())
            || (it->typeId() == QMetaType::Int && it->toInt() == 0))
            continue;
        out.insert(key, *it);
    }
    return out;
}

TagReader::TagReader(QObject *parent)
    : QObject(parent)
{
    m_pool.setMaxThreadCount(1);
}

TagReader::~TagReader()
{
    m_generation.fetchAndAddOrdered(1);
    m_pool.waitForDone();
}

void TagReader::setCacheFile(const QString &file)
{
    if (m_cacheFile == file)
        return;
    m_cacheFile = file;
    Q_EMIT cacheFileChanged();
}

void TagReader::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    Q_EMIT busyChanged();
}

QVariantMap TagReader::read(const QString &path) const
{
    const Tags::TrackInfo info = Tags::read(path, true);
    QVariantMap map = Tags::toVariantMap(info);
    if (!map.contains(QStringLiteral("lyrics"))) {
        const QString sidecar = Tags::sidecarLyrics(path);
        if (!sidecar.isEmpty())
            map.insert(QStringLiteral("lyrics"), sidecar);
    }
    const QFileInfo file(path);
    map.insert(QStringLiteral("path"), path);
    map.insert(QStringLiteral("size"), static_cast<double>(file.size()));
    map.insert(QStringLiteral("format"), file.suffix().toUpper());
    return map;
}

void TagReader::cancel()
{
    m_generation.fetchAndAddOrdered(1);
    setBusy(false);
}

void TagReader::enrich(const QVariantList &songs)
{
    const int generation = m_generation.fetchAndAddOrdered(1) + 1;
    setBusy(true);

    struct Song { QString path; qint64 modified; };
    QList<Song> list;
    list.reserve(songs.size());
    for (const QVariant &v : songs) {
        const QVariantMap m = v.toMap();
        const QString path = m.value(QStringLiteral("path")).toString();
        if (!path.isEmpty())
            list.append(Song{path, static_cast<qint64>(m.value(QStringLiteral("modified")).toDouble())});
    }
    const QString file = m_cacheFile;
    QAtomicInt *latest = &m_generation;

    m_pool.start([this, list, file, generation, latest]() {
        auto current = [latest, generation]() { return latest->loadAcquire() == generation; };
        auto send = [this, generation](const QVariantList &batch) {
            if (batch.isEmpty())
                return;
            QMetaObject::invokeMethod(this, [this, batch, generation]() {
                if (m_generation.loadAcquire() == generation)
                    Q_EMIT enriched(batch);
            }, Qt::QueuedConnection);
        };

        QMutexLocker locker(&m_indexLock);
        TagIndex index(file);
        if (!file.isEmpty())
            index.load();

        // What is known goes out first, so the lists fill in at once.
        QVariantList batch;
        QList<Song> unknown;
        QSet<QString> present;
        for (const Song &song : list) {
            // Gone since the indexer saw it (or the indexer could not write
            // its removal): reported, so the library leaves it out, and
            // dropped from the cache.
            if (!QFileInfo::exists(song.path)) {
                batch.append(QVariantMap{{QStringLiteral("path"), song.path},
                                         {QStringLiteral("missing"), true}});
                continue;
            }
            present.insert(song.path);
            QVariantMap fields;
            if (index.lookup(song.path, song.modified, &fields)) {
                fields.insert(QStringLiteral("path"), song.path);
                batch.append(fields);
                if (batch.size() >= batchSize) {
                    send(batch);
                    batch.clear();
                }
            } else {
                unknown.append(song);
            }
        }
        send(batch);
        batch.clear();

        bool changed = index.prune(present) > 0;
        for (const Song &song : unknown) {
            if (!current())
                break;
            const Tags::TrackInfo info = Tags::read(song.path, false);
            QVariantMap fields = TagIndex::cachedFields(Tags::toVariantMap(info));
            // An unreadable file is remembered too, so it is not tried every start.
            index.insert(song.path, song.modified, fields);
            changed = true;
            fields.insert(QStringLiteral("path"), song.path);
            batch.append(fields);
            if (batch.size() >= batchSize) {
                send(batch);
                batch.clear();
            }
        }
        send(batch);
        if (changed && !file.isEmpty())
            index.save();

        QMetaObject::invokeMethod(this, [this, generation]() {
            if (m_generation.loadAcquire() != generation)
                return;
            setBusy(false);
            Q_EMIT finished();
        }, Qt::QueuedConnection);
    });
}
