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

#include "playlistfiles.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QRegularExpression>
#include <QtCore/QSaveFile>
#include <QtCore/QStringDecoder>
#include <QtCore/QUrl>

namespace PlaylistFiles {

// Larger than any playlist; a file this big is not one.
constexpr qint64 maxPlaylistBytes = qint64(4) * 1024 * 1024;

namespace {

QString decode(const QByteArray &content)
{
    QByteArray bytes = content;
    if (bytes.startsWith("\xEF\xBB\xBF"))
        bytes.remove(0, 3);
    // M3U8 is UTF-8; a plain .m3u from an old Windows player is often
    // Latin-1, which is the fallback when the bytes are not valid UTF-8.
    QStringDecoder utf8(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
    QString text = utf8.decode(bytes);
    if (utf8.hasError())
        text = QString::fromLatin1(bytes);
    return text;
}

QString resolve(QString entry, const QString &baseDir)
{
    entry = entry.trimmed();
    if (entry.isEmpty() || entry.startsWith(QLatin1Char('#')))
        return QString();
    if (entry.startsWith(QLatin1String("file:"), Qt::CaseInsensitive)) {
        const QUrl url(entry);
        if (!url.isLocalFile())
            return QString();
        entry = url.toLocalFile();
    } else if (entry.contains(QLatin1String("://"))) {
        return QString();
    }
    entry.replace(QLatin1Char('\\'), QLatin1Char('/'));
    // "C:/Music/..." from a Windows machine: only its relative tail can mean
    // anything here, and that is guessed at from baseDir below.
    static const QRegularExpression drive(QStringLiteral("^[A-Za-z]:/"));
    if (drive.match(entry).hasMatch())
        entry = entry.mid(3);
    if (!QDir::isAbsolutePath(entry))
        entry = QDir(baseDir).filePath(entry);
    return QDir::cleanPath(entry);
}

} // namespace

QStringList parse(const QByteArray &content, const QString &baseDir)
{
    QStringList tracks;
    const QString text = decode(content);
    const QStringList lines = text.split(QRegularExpression(QStringLiteral("[\r\n]+")), Qt::SkipEmptyParts);

    const bool pls = lines.value(0).trimmed().compare(QLatin1String("[playlist]"), Qt::CaseInsensitive) == 0;
    static const QRegularExpression plsFile(QStringLiteral("^\\s*File\\d+\\s*=\\s*(.*)$"),
                                            QRegularExpression::CaseInsensitiveOption);
    for (const QString &line : lines) {
        QString entry = line;
        if (pls) {
            const QRegularExpressionMatch m = plsFile.match(line);
            if (!m.hasMatch())
                continue;
            entry = m.captured(1);
        }
        const QString path = resolve(entry, baseDir);
        if (!path.isEmpty())
            tracks.append(path);
    }
    return tracks;
}

QByteArray writeM3u8(const QVariantList &tracks, const QString &baseDir)
{
    const QDir base(baseDir);
    const QString prefix = QDir::cleanPath(baseDir) + QLatin1Char('/');
    QByteArray out("#EXTM3U\n");
    for (const QVariant &v : tracks) {
        const QVariantMap track = v.toMap();
        const QString path = QDir::cleanPath(track.value(QStringLiteral("path")).toString());
        if (path.isEmpty())
            continue;
        const qint64 seconds = static_cast<qint64>(track.value(QStringLiteral("duration")).toDouble() / 1000.0);
        const QString artist = track.value(QStringLiteral("artist")).toString();
        QString title = track.value(QStringLiteral("title")).toString();
        if (title.isEmpty())
            title = QFileInfo(path).completeBaseName();
        QString display = artist.isEmpty() ? title : artist + QLatin1String(" - ") + title;
        display.replace(QLatin1Char('\n'), QLatin1Char(' '));
        out += "#EXTINF:" + QByteArray::number(seconds > 0 ? seconds : -1) + ',' + display.toUtf8() + '\n';
        out += (path.startsWith(prefix) ? base.relativeFilePath(path) : path).toUtf8() + '\n';
    }
    return out;
}

QString safeFileName(const QString &name)
{
    QString out;
    out.reserve(name.size());
    for (const QChar c : name) {
        if (c.unicode() < 0x20 || QStringLiteral("/\\:*?\"<>|").contains(c))
            out += QLatin1Char('_');
        else
            out += c;
    }
    out = out.trimmed();
    while (out.startsWith(QLatin1Char('.')))
        out.remove(0, 1);
    if (out.size() > 120)
        out.truncate(120);
    return out.isEmpty() ? QStringLiteral("Playlist") : out;
}

} // namespace PlaylistFiles

PlaylistIO::PlaylistIO(QObject *parent)
    : QObject(parent)
{
}

void PlaylistIO::setExportDir(const QString &dir)
{
    if (m_exportDir == dir)
        return;
    m_exportDir = dir;
    Q_EMIT exportDirChanged();
}

bool PlaylistIO::isPlaylistFile(const QString &path)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    return suffix == QLatin1String("m3u") || suffix == QLatin1String("m3u8") || suffix == QLatin1String("pls");
}

QStringList PlaylistIO::read(const QString &path) const
{
    QFile file(path);
    if (!isPlaylistFile(path) || file.size() > PlaylistFiles::maxPlaylistBytes || !file.open(QIODevice::ReadOnly))
        return QStringList();
    const QStringList all = PlaylistFiles::parse(file.readAll(), QFileInfo(path).absolutePath());
    QStringList existing;
    for (const QString &track : all) {
        if (QFileInfo(track).isFile())
            existing.append(track);
    }
    return existing;
}

QString PlaylistIO::write(const QString &name, const QVariantList &tracks) const
{
    if (m_exportDir.isEmpty() || !QDir().mkpath(m_exportDir))
        return QString();
    const QString root = QFileInfo(m_exportDir).canonicalFilePath();
    const QString target = QDir(root).filePath(PlaylistFiles::safeFileName(name) + QLatin1String(".m3u8"));
    // safeFileName() leaves no separator, so this only fails on a symlink
    // planted in the way; checked all the same.
    if (QFileInfo(target).absolutePath() != root || QFileInfo(target).isSymLink())
        return QString();
    QSaveFile file(target);
    if (!file.open(QIODevice::WriteOnly))
        return QString();
    file.write(PlaylistFiles::writeM3u8(tracks, root));
    return file.commit() ? target : QString();
}
