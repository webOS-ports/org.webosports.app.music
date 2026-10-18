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

#ifndef TAGS_H
#define TAGS_H

#include <QtCore/QByteArray>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantMap>

/*
 * What TagLib can tell about a track that the media indexer does not store:
 * the length (the indexer writes 0), the year, the composer, ReplayGain,
 * the lyrics and the cover picture. MP3 (ID3v1/v2), MP4/M4A, FLAC, Ogg
 * Vorbis/Opus, WMA, WAV, AIFF and APE all go through the same TagLib calls.
 */
namespace Tags {

struct TrackInfo
{
    bool valid = false;
    QString title;
    QString artist;
    QString albumArtist;
    QString album;
    QString genre;
    QString composer;
    int year = 0;
    int track = 0;
    int trackTotal = 0;
    int disc = 0;
    int discTotal = 0;
    int durationMs = 0;
    int bitrate = 0;        // kbit/s
    int sampleRate = 0;     // Hz
    int channels = 0;
    // ReplayGain in dB and peaks as a fraction of full scale; hasXxx says
    // whether the tag was there at all (0 dB is a valid gain).
    bool hasTrackGain = false;
    bool hasAlbumGain = false;
    double trackGain = 0;
    double albumGain = 0;
    double trackPeak = 0;
    double albumPeak = 0;
    QString lyrics;
};

/// Reads the tags and audio properties of one file. Lyrics are only read
/// when asked for: they can be long and the library has no use for them.
TrackInfo read(const QString &path, bool withLyrics = false);

/// The fields QML uses, with the gains left out when not tagged.
QVariantMap toVariantMap(const TrackInfo &info);

/// "-6.53 dB", "+1.2 dB", "-6.53" -> the number; false when it is none.
bool parseGain(const QString &text, double *gain);

/// "3/12" -> 3 and total 12; "3" -> 3 and total untouched; 0 when none.
int parseNumberPair(const QString &text, int *total);

/// "2009-04-01", "2009", "April 2009" -> 2009; 0 when there is no year.
int parseYear(const QString &text);

/// The embedded cover: the front cover when the file says which picture
/// that is, otherwise the first picture. Empty when there is none.
QByteArray embeddedCover(const QString &path);

/// A cover image next to the file, as rippers and stores leave them
/// (cover.jpg, folder.jpg, front.png, AlbumArt_..._Large.jpg, ...), or the
/// only image in the folder. "" when there is none.
QString folderCover(const QString &dir);

/// Is this folder name a disc of a set ("CD1", "Disc 2", "disk_03",
/// "Vol. 2")? Its album's cover is then usually one folder up.
bool isDiscFolder(const QString &name);

/// The lyrics in a sidecar file next to the track ("Song.lrc", then
/// "Song.txt"), as text. "" when there is none or it is too large.
QString sidecarLyrics(const QString &path);

/// The file name extensions (lower case, no dot) of the audio files the app
/// lists and plays.
const QStringList &audioExtensions();

bool isAudioFile(const QString &path);

} // namespace Tags

#endif // TAGS_H
