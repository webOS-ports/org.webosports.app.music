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

#ifndef TAGCACHE_H
#define TAGCACHE_H

#include <QtCore/QAtomicInt>
#include <QtCore/QHash>
#include <QtCore/QMutex>
#include <QtCore/QObject>
#include <QtCore/QSet>
#include <QtCore/QThreadPool>
#include <QtCore/QVariantList>
#include <QtCore/QVariantMap>

/*
 * The fields the media indexer leaves out (length, year, composer,
 * ReplayGain), read once per file with TagLib and kept in a JSON file, so
 * the next start has them at once. An entry is read again when the file's
 * modification time changes.
 */
class TagIndex
{
public:
    struct Entry
    {
        qint64 modified = 0;    // ms since the epoch, as the indexer gives it
        QVariantMap fields;
    };

    explicit TagIndex(const QString &file);

    bool load();
    bool save() const;

    /// The fields for path, if they were read at that modification time.
    bool lookup(const QString &path, qint64 modified, QVariantMap *fields) const;
    void insert(const QString &path, qint64 modified, const QVariantMap &fields);
    /// Leaves out every entry whose path is not in keep (deleted files).
    int prune(const QSet<QString> &keep);
    int size() const { return static_cast<int>(m_entries.size()); }

    /// The cached part of what Tags::read() gives: what the lists and the
    /// player need, no titles (the indexer has those) and no lyrics.
    static QVariantMap cachedFields(const QVariantMap &all);

private:
    QString m_file;
    QHash<QString, Entry> m_entries;
};

/*
 * The QML side: reads the tags of one file now, or fills in a whole library
 * in the background.
 *
 *     TagReader {
 *         onEnriched: (batch) => library.merge(batch)
 *     }
 *     tagReader.enrich(songs.map(s => ({ path: s.path, modified: s.modifiedTime })))
 */
class TagReader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString cacheFile READ cacheFile WRITE setCacheFile NOTIFY cacheFileChanged)

public:
    explicit TagReader(QObject *parent = nullptr);
    ~TagReader() override;

    bool busy() const { return m_busy; }
    QString cacheFile() const { return m_cacheFile; }
    void setCacheFile(const QString &file);

    /// Everything about one file, lyrics included (embedded, else a
    /// sidecar .lrc/.txt), plus the file's size and format. Blocks: for the
    /// track about to play or the song info sheet, not for a list.
    Q_INVOKABLE QVariantMap read(const QString &path) const;

    /// For each { path, modified }, the cached fields; files not in the cache
    /// are read on a worker thread. Results come in enriched() batches, the
    /// cached ones first, then finished(). A new call stops the last one.
    Q_INVOKABLE void enrich(const QVariantList &songs);
    Q_INVOKABLE void cancel();

Q_SIGNALS:
    void busyChanged();
    void cacheFileChanged();
    /// [{ path, duration, year, composer, ... }]
    void enriched(const QVariantList &batch);
    void finished();

private:
    void setBusy(bool busy);

    QString m_cacheFile;
    bool m_busy = false;
    QAtomicInt m_generation;
    QMutex m_indexLock;     // one worker writes the cache file at a time
    QThreadPool m_pool;     // waited for on destruction, so no worker outlives this
};

#endif // TAGCACHE_H
