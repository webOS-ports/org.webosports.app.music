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

#include "plugin.h"
#include "artprovider.h"
#include "filebrowser.h"
#include "playlistfiles.h"
#include "tagcache.h"

#include <QtQml/QtQml>

void MusicAppPlugin::registerTypes(const char *uri)
{
    Q_ASSERT(uri == QLatin1String("MusicApp"));

    // @uri MusicApp
    qmlRegisterType<TagReader>(uri, 1, 0, "TagReader");
    qmlRegisterType<ArtAccent>(uri, 1, 0, "ArtAccent");
    qmlRegisterType<ArtCache>(uri, 1, 0, "ArtCache");
    qmlRegisterType<PlaylistIO>(uri, 1, 0, "PlaylistIO");
    qmlRegisterType<FileBrowser>(uri, 1, 0, "FileBrowser");
    qmlRegisterType<StateFile>(uri, 1, 0, "StateFile");
}

void MusicAppPlugin::initializeEngine(QQmlEngine *engine, const char *uri)
{
    Q_UNUSED(uri);
    // The engine owns the provider from here on.
    engine->addImageProvider(QStringLiteral("musicart"), new ArtProvider);
}
