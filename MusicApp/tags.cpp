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

#include "tags.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QRegularExpression>

#include <algorithm>

#include <taglib/audioproperties.h>
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>

namespace Tags {

namespace {

QString toQString(const TagLib::String &s)
{
    return QString::fromStdString(s.to8Bit(true)).trimmed();
}

QString first(const TagLib::PropertyMap &map, const char *key)
{
    const auto it = map.find(key);
    if (it == map.end() || it->second.isEmpty())
        return QString();
    return toQString(it->second.front());
}

// Lyrics files beyond this are not lyrics.
constexpr qint64 maxLyricsBytes = qint64(512) * 1024;

} // namespace

const QStringList &audioExtensions()
{
    static const QStringList extensions = {
        QStringLiteral("mp3"), QStringLiteral("m4a"), QStringLiteral("m4b"), QStringLiteral("mp4"),
        QStringLiteral("aac"), QStringLiteral("flac"), QStringLiteral("ogg"), QStringLiteral("oga"),
        QStringLiteral("opus"), QStringLiteral("wav"), QStringLiteral("wma"), QStringLiteral("aif"),
        QStringLiteral("aiff"), QStringLiteral("ape"), QStringLiteral("wv"), QStringLiteral("mka"),
    };
    return extensions;
}

bool isAudioFile(const QString &path)
{
    return audioExtensions().contains(QFileInfo(path).suffix().toLower());
}

bool parseGain(const QString &text, double *gain)
{
    static const QRegularExpression number(QStringLiteral("^\\s*([+-]?[0-9]+(?:[.,][0-9]+)?)\\s*(?:dB)?\\s*$"),
                                           QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = number.match(text);
    if (!m.hasMatch())
        return false;
    bool ok = false;
    const double value = m.captured(1).replace(QLatin1Char(','), QLatin1Char('.')).toDouble(&ok);
    // Anything past +-60 dB is a broken tag, not a gain to apply.
    if (!ok || value < -60.0 || value > 60.0)
        return false;
    *gain = value;
    return true;
}

int parseNumberPair(const QString &text, int *total)
{
    const QStringList parts = text.trimmed().split(QLatin1Char('/'));
    if (parts.isEmpty())
        return 0;
    bool ok = false;
    const int number = parts.at(0).trimmed().toInt(&ok);
    if (parts.size() > 1 && total) {
        bool totalOk = false;
        const int t = parts.at(1).trimmed().toInt(&totalOk);
        if (totalOk && t > 0)
            *total = t;
    }
    return ok && number > 0 ? number : 0;
}

int parseYear(const QString &text)
{
    static const QRegularExpression year(QStringLiteral("(?:^|[^0-9])([12][0-9]{3})(?:$|[^0-9])"));
    const QRegularExpressionMatch m = year.match(text);
    return m.hasMatch() ? m.captured(1).toInt() : 0;
}

TrackInfo read(const QString &path, bool withLyrics)
{
    TrackInfo info;
    const QByteArray encoded = QFile::encodeName(path);
    TagLib::FileRef ref(encoded.constData(), true, TagLib::AudioProperties::Average);
    // TagLib takes any file named .mp3 for one; without a sample rate it
    // found no audio in it.
    if (ref.isNull() || !ref.audioProperties() || ref.audioProperties()->sampleRate() <= 0)
        return info;
    info.valid = true;

    if (const TagLib::Tag *tag = ref.tag()) {
        info.title = toQString(tag->title());
        info.artist = toQString(tag->artist());
        info.album = toQString(tag->album());
        info.genre = toQString(tag->genre());
        info.year = static_cast<int>(tag->year());
        info.track = static_cast<int>(tag->track());
    }

    const TagLib::PropertyMap props = ref.properties();
    info.albumArtist = first(props, "ALBUMARTIST");
    info.composer = first(props, "COMPOSER");
    const QString trackText = first(props, "TRACKNUMBER");
    if (!trackText.isEmpty()) {
        const int n = parseNumberPair(trackText, &info.trackTotal);
        if (n > 0)
            info.track = n;
    }
    const QString totalTracks = first(props, "TRACKTOTAL");
    if (info.trackTotal == 0 && !totalTracks.isEmpty())
        info.trackTotal = qMax(0, totalTracks.toInt());
    info.disc = parseNumberPair(first(props, "DISCNUMBER"), &info.discTotal);
    const QString totalDiscs = first(props, "DISCTOTAL");
    if (info.discTotal == 0 && !totalDiscs.isEmpty())
        info.discTotal = qMax(0, totalDiscs.toInt());
    if (info.year == 0) {
        info.year = parseYear(first(props, "DATE"));
        if (info.year == 0)
            info.year = parseYear(first(props, "ORIGINALDATE"));
    }

    info.hasTrackGain = parseGain(first(props, "REPLAYGAIN_TRACK_GAIN"), &info.trackGain);
    info.hasAlbumGain = parseGain(first(props, "REPLAYGAIN_ALBUM_GAIN"), &info.albumGain);
    bool ok = false;
    const double tp = first(props, "REPLAYGAIN_TRACK_PEAK").toDouble(&ok);
    if (ok && tp > 0)
        info.trackPeak = tp;
    const double ap = first(props, "REPLAYGAIN_ALBUM_PEAK").toDouble(&ok);
    if (ok && ap > 0)
        info.albumPeak = ap;

    if (withLyrics) {
        // ID3 USLT, MP4 (c)lyr and Vorbis LYRICS all come out as LYRICS.
        const auto it = props.find("LYRICS");
        if (it != props.end() && !it->second.isEmpty())
            info.lyrics = QString::fromStdString(it->second.front().to8Bit(true));
    }

    const TagLib::AudioProperties *audio = ref.audioProperties();
    info.durationMs = audio->lengthInMilliseconds();
    info.bitrate = audio->bitrate();
    info.sampleRate = audio->sampleRate();
    info.channels = audio->channels();
    return info;
}

QVariantMap toVariantMap(const TrackInfo &info)
{
    QVariantMap map;
    map.insert(QStringLiteral("valid"), info.valid);
    map.insert(QStringLiteral("title"), info.title);
    map.insert(QStringLiteral("artist"), info.artist);
    map.insert(QStringLiteral("albumArtist"), info.albumArtist);
    map.insert(QStringLiteral("album"), info.album);
    map.insert(QStringLiteral("genre"), info.genre);
    map.insert(QStringLiteral("composer"), info.composer);
    map.insert(QStringLiteral("year"), info.year);
    map.insert(QStringLiteral("track"), info.track);
    map.insert(QStringLiteral("trackTotal"), info.trackTotal);
    map.insert(QStringLiteral("disc"), info.disc);
    map.insert(QStringLiteral("discTotal"), info.discTotal);
    map.insert(QStringLiteral("duration"), info.durationMs);
    map.insert(QStringLiteral("bitrate"), info.bitrate);
    map.insert(QStringLiteral("sampleRate"), info.sampleRate);
    map.insert(QStringLiteral("channels"), info.channels);
    if (info.hasTrackGain)
        map.insert(QStringLiteral("trackGain"), info.trackGain);
    if (info.hasAlbumGain)
        map.insert(QStringLiteral("albumGain"), info.albumGain);
    if (info.trackPeak > 0)
        map.insert(QStringLiteral("trackPeak"), info.trackPeak);
    if (info.albumPeak > 0)
        map.insert(QStringLiteral("albumPeak"), info.albumPeak);
    if (!info.lyrics.isEmpty())
        map.insert(QStringLiteral("lyrics"), info.lyrics);
    return map;
}

QByteArray embeddedCover(const QString &path)
{
    const QByteArray encoded = QFile::encodeName(path);
    TagLib::FileRef ref(encoded.constData(), false);
    if (ref.isNull())
        return QByteArray();

    const TagLib::List<TagLib::VariantMap> pictures = ref.complexProperties("PICTURE");
    const TagLib::VariantMap *chosen = nullptr;
    for (const TagLib::VariantMap &picture : pictures) {
        const auto data = picture.find("data");
        if (data == picture.end() || data->second.toByteVector().isEmpty())
            continue;
        if (!chosen)
            chosen = &picture;
        const auto type = picture.find("pictureType");
        if (type != picture.end() && type->second.toString() == "Front Cover") {
            chosen = &picture;
            break;
        }
    }
    if (!chosen)
        return QByteArray();
    const TagLib::ByteVector bytes = chosen->find("data")->second.toByteVector();
    return QByteArray(bytes.data(), static_cast<qsizetype>(bytes.size()));
}

QString folderCover(const QString &dir)
{
    const QDir folder(dir);
    if (dir.isEmpty() || !folder.exists())
        return QString();
    const QStringList images = folder.entryList({QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"),
                                                 QStringLiteral("*.png"), QStringLiteral("*.webp")},
                                                QDir::Files | QDir::Readable, QDir::Name | QDir::IgnoreCase);
    if (images.isEmpty())
        return QString();

    // In order of how sure a name is to be the front cover.
    static const QStringList preferred = {
        QStringLiteral("cover"), QStringLiteral("folder"), QStringLiteral("front"),
        QStringLiteral("album"), QStringLiteral("albumart"), QStringLiteral("albumartlarge"),
    };
    auto firstMatching = [&images](auto matches) {
        const auto it = std::find_if(images.cbegin(), images.cend(), matches);
        return it != images.cend() ? *it : QString();
    };
    for (const QString &name : preferred) {
        const QString found = firstMatching([&name](const QString &image) {
            return QFileInfo(image).completeBaseName().compare(name, Qt::CaseInsensitive) == 0;
        });
        if (!found.isEmpty())
            return folder.filePath(found);
    }
    // Windows Media Player's AlbumArt_{GUID}_Large.jpg.
    QString found = firstMatching([](const QString &image) {
        return image.startsWith(QLatin1String("AlbumArt"), Qt::CaseInsensitive)
               && image.contains(QLatin1String("Large"), Qt::CaseInsensitive);
    });
    if (found.isEmpty()) {
        found = firstMatching([](const QString &image) {
            const QString base = QFileInfo(image).completeBaseName().toLower();
            return base.contains(QLatin1String("cover")) || base.contains(QLatin1String("front"));
        });
    }
    if (!found.isEmpty())
        return folder.filePath(found);
    // A single picture in an album's folder is its cover; several are a
    // booklet, and guessing would as likely pick the back.
    if (images.size() == 1)
        return folder.filePath(images.first());
    return QString();
}

bool isDiscFolder(const QString &name)
{
    static const QRegularExpression disc(QStringLiteral("^(cd|disc|disk|vol(ume)?)[\\s._-]*\\d+$"),
                                         QRegularExpression::CaseInsensitiveOption);
    return disc.match(name).hasMatch();
}

QString sidecarLyrics(const QString &path)
{
    const QFileInfo track(path);
    const QString base = track.dir().filePath(track.completeBaseName());
    for (const char *ext : {".lrc", ".LRC", ".txt"}) {
        QFile file(base + QLatin1String(ext));
        if (!file.exists() || file.size() > maxLyricsBytes || !file.open(QIODevice::ReadOnly))
            continue;
        // fromUtf8 drops a leading byte-order mark itself.
        return QString::fromUtf8(file.readAll());
    }
    return QString();
}

} // namespace Tags
