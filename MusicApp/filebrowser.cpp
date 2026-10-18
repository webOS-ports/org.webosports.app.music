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

#include "filebrowser.h"
#include "playlistfiles.h"
#include "tags.h"

#include <QtCore/QCollator>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QRegularExpression>
#include <QtCore/QSaveFile>

#include <algorithm>

namespace {

QFileInfoList sortedEntries(const QString &dir)
{
    QDir folder(dir);
    QFileInfoList entries = folder.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Readable);
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(entries.begin(), entries.end(), [&collator](const QFileInfo &a, const QFileInfo &b) {
        if (a.isDir() != b.isDir())
            return a.isDir();
        return collator.compare(a.fileName(), b.fileName()) < 0;
    });
    return entries;
}

bool listed(const QFileInfo &info)
{
    if (info.fileName().startsWith(QLatin1Char('.')))
        return false;
    if (info.isDir())
        return true;
    return Tags::isAudioFile(info.fileName()) || PlaylistIO::isPlaylistFile(info.fileName());
}

void collect(const QString &dir, int limit, int depth, QStringList *out)
{
    // Deep enough for Artist/Album/Disc/..., and a stop for symlink loops.
    if (depth > 12)
        return;
    const QFileInfoList entries = sortedEntries(dir);
    for (const QFileInfo &info : entries) {
        if (out->size() >= limit)
            return;
        if (info.fileName().startsWith(QLatin1Char('.')))
            continue;
        if (info.isDir() && !info.isSymLink())
            collect(info.filePath(), limit, depth + 1, out);
        else if (info.isFile() && Tags::isAudioFile(info.fileName()))
            out->append(info.filePath());
    }
}

} // namespace

FileBrowser::FileBrowser(QObject *parent)
    : QObject(parent)
{
}

QVariantList FileBrowser::roots(const QString &internalPath, const QString &mediaRoot) const
{
    QVariantList out;
    if (QFileInfo(internalPath).isDir())
        out.append(QVariantMap{{QStringLiteral("name"), tr("Internal storage")}, {QStringLiteral("path"), internalPath}});
    const QString internalCanonical = QFileInfo(internalPath).canonicalFilePath();
    const QFileInfoList mounts = QDir(mediaRoot).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable, QDir::Name);
    // Folders under /media that are LuneOS's own, not removable storage.
    static const QStringList system = {
        QStringLiteral("internal"), QStringLiteral("cryptofs"), QStringLiteral("developer"),
        QStringLiteral("ram"), QStringLiteral("var"),
    };
    for (const QFileInfo &mount : mounts) {
        if (system.contains(mount.fileName()) || mount.canonicalFilePath() == internalCanonical)
            continue;
        // An empty mount point is a card that is not in.
        if (QDir(mount.filePath()).isEmpty())
            continue;
        out.append(QVariantMap{{QStringLiteral("name"), mount.fileName()}, {QStringLiteral("path"), mount.filePath()}});
    }
    return out;
}

QVariantList FileBrowser::list(const QString &dir) const
{
    QVariantList out;
    const QFileInfoList entries = sortedEntries(dir);
    for (const QFileInfo &info : entries) {
        if (!listed(info))
            continue;
        out.append(QVariantMap{
            {QStringLiteral("name"), info.fileName()},
            {QStringLiteral("path"), info.filePath()},
            {QStringLiteral("isDir"), info.isDir()},
            {QStringLiteral("isPlaylist"), info.isFile() && PlaylistIO::isPlaylistFile(info.fileName())},
            {QStringLiteral("modified"), static_cast<double>(info.lastModified().toMSecsSinceEpoch())},
        });
    }
    return out;
}

QStringList FileBrowser::audioFilesUnder(const QString &dir, int limit) const
{
    QStringList out;
    if (limit > 0 && QFileInfo(dir).isDir())
        collect(dir, limit, 0, &out);
    return out;
}

bool FileBrowser::exists(const QString &path) const
{
    return !path.isEmpty() && QFileInfo::exists(path);
}

QString FileBrowser::folderOf(const QString &path) const
{
    return QFileInfo(path).absolutePath();
}

StateFile::StateFile(QObject *parent)
    : QObject(parent)
{
}

void StateFile::setDirectory(const QString &dir)
{
    if (m_directory == dir)
        return;
    m_directory = dir;
    Q_EMIT directoryChanged();
}

bool StateFile::isValidName(const QString &name)
{
    static const QRegularExpression valid(QStringLiteral("^[a-z0-9][a-z0-9-]{0,63}$"));
    return valid.match(name).hasMatch();
}

QString StateFile::load(const QString &name) const
{
    if (m_directory.isEmpty() || !isValidName(name))
        return QString();
    QFile file(QDir(m_directory).filePath(name + QLatin1String(".json")));
    if (!file.open(QIODevice::ReadOnly))
        return QString();
    return QString::fromUtf8(file.readAll());
}

bool StateFile::save(const QString &name, const QString &text) const
{
    if (m_directory.isEmpty() || !isValidName(name) || !QDir().mkpath(m_directory))
        return false;
    QSaveFile file(QDir(m_directory).filePath(name + QLatin1String(".json")));
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(text.toUtf8());
    return file.commit();
}
