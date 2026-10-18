#!/bin/sh
# Rebuilds tests/fixtures/music: a small library of generated tones with
# the tags the app has to handle - embedded covers (MP3), a folder.jpg
# (FLAC), a two-disc album in CD1/CD2 folders, a compilation without
# album artist tags (Ogg), ReplayGain, an LRC sidecar and an M3U with a
# relative path, a Windows path and a stream. Needs ffmpeg and ImageMagick.
set -e
cd "$(dirname "$0")"
rm -rf music
magick -size 300x300 gradient:'#c0392b-#8e44ad' cover-red.jpg
magick -size 200x200 xc:'#2e86c1' -fill white -draw "circle 100,100 100,40" folder-blue.jpg
mkdir -p "music/Ana Ray/Red Sky" "music/Blue Band/Deep Water/CD1" "music/Blue Band/Deep Water/CD2" "music/Various/Summer Mix"
for i in 1 2 3; do
    ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((400 + i * 50)):duration=3" -i cover-red.jpg \
        -map 0 -map 1 -c:a libmp3lame -b:a 64k -c:v mjpeg -id3v2_version 3 -metadata:s:v comment="Cover (front)" \
        -metadata title="Red Song $i" -metadata artist="Ana Ray" -metadata album="Red Sky" -metadata track="$i/3" \
        -metadata date=2019 -metadata genre=Pop -metadata REPLAYGAIN_TRACK_GAIN="-$i.50 dB" \
        -metadata REPLAYGAIN_ALBUM_GAIN="-2.00 dB" "music/Ana Ray/Red Sky/0$i Red Song $i.mp3"
done
cp folder-blue.jpg "music/Blue Band/Deep Water/folder.jpg"
for d in 1 2; do
    for i in 1 2; do
        ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((300 + d * 100 + i * 30)):duration=3" \
            -metadata title="Deep $d-$i" -metadata artist="Blue Band" -metadata album="Deep Water" -metadata track="$i" \
            -metadata disc="$d/2" -metadata date=2021 -metadata genre=Rock "music/Blue Band/Deep Water/CD$d/0$i Deep $d-$i.flac"
    done
done
k=1
for a in "Ana Ray" "Cool Cats" "Zed"; do
    ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((500 + k * 40)):duration=3" -c:a libvorbis \
        -metadata title="Sun $k" -metadata artist="$a" -metadata album="Summer Mix" -metadata track="$k" \
        -metadata date=2020 -metadata genre=Dance "music/Various/Summer Mix/0$k $a - Sun.ogg"
    k=$((k + 1))
done
printf '[ar:Ana Ray]\n[00:00.50]First line\n[00:01.50][00:02.50]Chorus line\n' > "music/Ana Ray/Red Sky/01 Red Song 1.lrc"
printf '#EXTM3U\n#EXTINF:3,Ana Ray - Red Song 2\nAna Ray/Red Sky/02 Red Song 2.mp3\nBlue Band\\Deep Water\\CD1\\01 Deep 1-1.flac\nhttp://example.com/stream\n' > music/mix.m3u
