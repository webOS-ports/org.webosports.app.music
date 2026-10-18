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

#ifndef PLAYLISTFILES_H
#define PLAYLISTFILES_H

#include <QtCore/QByteArray>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>

/*
 * Playlist files: M3U/M3U8 and PLS in, M3U8 out, so playlists can come
 * from and go to a computer (or another player) over USB.
 */
namespace PlaylistFiles {

/// The tracks a playlist file names, as absolute paths. Relative entries
/// are taken from baseDir (the playlist's folder); file:// URLs are
/// decoded; Windows separators are turned round; comments, #EXTINF lines
/// and streams (http://) are skipped.
QStringList parse(const QByteArray &content, const QString &baseDir);

/// An extended M3U8 of tracks [{ path, title, artist, duration (ms) }].
/// Tracks under baseDir are written relative to it, so the playlist and its
/// music can be moved together.
QByteArray writeM3u8(const QVariantList &tracks, const QString &baseDir);

/// A playlist name made safe as a file name: no separators, no control or
/// reserved characters, not empty, not hidden.
QString safeFileName(const QString &name);

} // namespace PlaylistFiles

/*
 * QML's way to the functions above.
 *
 * Writing is confined to exportDir and its subfolders: a playlist name from
 * QML cannot write a file anywhere else.
 */
class PlaylistIO : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString exportDir READ exportDir WRITE setExportDir NOTIFY exportDirChanged)

public:
    explicit PlaylistIO(QObject *parent = nullptr);

    QString exportDir() const { return m_exportDir; }
    void setExportDir(const QString &dir);

    /// The tracks of the playlist file at path that exist; [] when it
    /// cannot be read.
    Q_INVOKABLE QStringList read(const QString &path) const;

    /// Writes tracks as exportDir/<name>.m3u8, replacing an older export of
    /// the same name. Returns the file's path, or "" on failure.
    Q_INVOKABLE QString write(const QString &name, const QVariantList &tracks) const;

    Q_INVOKABLE static bool isPlaylistFile(const QString &path);

Q_SIGNALS:
    void exportDirChanged();

private:
    QString m_exportDir;
};

#endif // PLAYLISTFILES_H
