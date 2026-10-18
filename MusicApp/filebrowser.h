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

#ifndef FILEBROWSER_H
#define FILEBROWSER_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>

/*
 * The Folders view: music as it is laid out on the device, for people who
 * keep it in folders, and for cards and USB sticks the media indexer does
 * not scan.
 */
class FileBrowser : public QObject
{
    Q_OBJECT

public:
    explicit FileBrowser(QObject *parent = nullptr);

    /// The places to start from: the internal storage, and anything mounted
    /// under mediaRoot that is not the internal storage itself, as
    /// [{ name, path }].
    Q_INVOKABLE QVariantList roots(const QString &internalPath, const QString &mediaRoot) const;

    /// The folders, audio files and playlist files in dir, as
    /// [{ name, path, isDir, isPlaylist, modified (ms) }], folders first and
    /// then by name the way people read numbers ("2" before "10"). Hidden
    /// files and folders are left out.
    Q_INVOKABLE QVariantList list(const QString &dir) const;

    /// Every audio file under dir, sorted as list() sorts them, folder by
    /// folder; at most limit of them.
    Q_INVOKABLE QStringList audioFilesUnder(const QString &dir, int limit = 5000) const;

    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE QString folderOf(const QString &path) const;
};

/*
 * A small text file per name in the app's data folder, written whole and
 * atomically: the play queue, which is too large for Settings.
 */
class StateFile : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString directory READ directory WRITE setDirectory NOTIFY directoryChanged)

public:
    explicit StateFile(QObject *parent = nullptr);

    QString directory() const { return m_directory; }
    void setDirectory(const QString &dir);

    /// The text stored under name, "" when there is none. Names are
    /// lower-case letters, digits and "-" only.
    Q_INVOKABLE QString load(const QString &name) const;
    Q_INVOKABLE bool save(const QString &name, const QString &text) const;

    static bool isValidName(const QString &name);

Q_SIGNALS:
    void directoryChanged();

private:
    QString m_directory;
};

#endif // FILEBROWSER_H
