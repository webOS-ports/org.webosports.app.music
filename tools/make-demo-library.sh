#!/bin/sh
# A small, licence-free music library for screenshots and demos: made-up
# artists and albums, generated covers, tones of realistic length at a
# tiny bit rate (about 7 MB in all, mostly covers), a compilation, a two-disc album,
# ReplayGain tags and one song with synced lyrics.
#
#   tools/make-demo-library.sh <output dir>
#
# Needs ffmpeg and ImageMagick. Copy the result to /media/internal/Music on
# a device and let the media indexer find it.
set -e
OUT=${1:?usage: make-demo-library.sh <output dir>}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
TMP=$OUT/.covers
mkdir -p "$TMP"

# cover <file> <colour 1> <colour 2> <shape> <title>
cover() {
    f=$1; c1=$2; c2=$3; shape=$4; title=$5
    case $shape in
    circles) draw="fill rgba(255,255,255,0.35) circle 380,220 380,90 fill rgba(255,255,255,0.18) circle 200,420 200,300" ;;
    stripes) draw="fill rgba(255,255,255,0.22) polygon 0,600 600,0 600,120 120,600 fill rgba(255,255,255,0.12) polygon 0,360 360,0 460,0 0,460" ;;
    rings)   draw="fill none stroke rgba(255,255,255,0.5) stroke-width 18 circle 300,300 300,130 stroke-width 8 circle 300,300 300,60" ;;
    sun)     draw="fill rgba(255,230,160,0.8) circle 300,360 300,250 fill rgba(0,0,0,0.25) rectangle 0,380 600,600" ;;
    grid)    draw="fill none stroke rgba(255,255,255,0.25) stroke-width 3 path 'M 0,150 L 600,150 M 0,300 L 600,300 M 0,450 L 600,450 M 150,0 L 150,600 M 300,0 L 300,600 M 450,0 L 450,600'" ;;
    tiles)   draw="fill rgba(255,255,255,0.28) rectangle 90,90 290,290 fill rgba(255,255,255,0.16) rectangle 310,90 510,290 fill rgba(255,255,255,0.16) rectangle 90,310 290,510 fill rgba(255,255,255,0.4) rectangle 310,310 510,510" ;;
    *)       draw="fill rgba(255,255,255,0.3) rectangle 140,140 460,460" ;;
    esac
    magick -size 600x600 "gradient:$c1-$c2" -draw "$draw" \
        -gravity south -fill white -pointsize 44 -annotate +0+40 "$title" "$f"
}

# track <file> <title> <artist> <album> <album artist|-> <track/total> <disc|-> <year> <genre> <seconds> <hz> [cover]
track() {
    f=$1; title=$2; artist=$3; album=$4; aa=$5; trk=$6; disc=$7; year=$8; genre=$9; shift 9
    secs=$1; hz=$2; art=$3
    mkdir -p "$(dirname "$f")"
    # A soft chord rather than a bare sine; mono, 8 kHz, 8 kbit/s.
    set -- -f lavfi -i "aevalsrc=0.2*sin($hz*2*PI*t)+0.12*sin($hz*1.5*2*PI*t)+0.08*sin($hz*1.25*2*PI*t):s=8000:d=$secs"
    if [ -n "$art" ]; then
        set -- "$@" -i "$art" -map 0 -map 1 -c:v mjpeg -metadata:s:v comment="Cover (front)"
    fi
    set -- "$@" -c:a libmp3lame -b:a 8k -ac 1 -id3v2_version 3 \
        -metadata title="$title" -metadata artist="$artist" -metadata album="$album" \
        -metadata track="$trk" -metadata date="$year" -metadata genre="$genre" \
        -metadata REPLAYGAIN_TRACK_GAIN="-$(( (${#title} % 5) + 3 )).$(( ${#artist} % 10 ))0 dB" \
        -metadata REPLAYGAIN_ALBUM_GAIN="-5.20 dB"
    [ "$aa" != "-" ] && set -- "$@" -metadata album_artist="$aa"
    [ "$disc" != "-" ] && set -- "$@" -metadata disc="$disc"
    ffmpeg -loglevel error -y "$@" "$f"
}

M=$OUT
cover "$TMP/northern.jpg" '#0b3d63' '#2bb1c7' rings  "Northern Lights"
cover "$TMP/paper.jpg"    '#f5a65b' '#c2185b' circles "Paper Moons"
cover "$TMP/static.jpg"   '#1d1d2b' '#7b4397' grid   "Static Bloom"
cover "$TMP/harbour.jpg"  '#004d40' '#9ccc65' stripes "Harbour Songs"
cover "$TMP/summer.jpg"   '#ff7e5f' '#feb47b' sun    "Summer Radio"
cover "$TMP/glass1.jpg"   '#134e5e' '#71b280' tiles  "Glass Garden"

i=1; for t in "Aurora" "Cold Coast" "Polar Night" "Driftwood" "Snowfield"; do
    track "$M/Lumen Avenue/Northern Lights/0$i $t.mp3" "$t" "Lumen Avenue" "Northern Lights" - "$i/5" - 2023 Ambient $((180 + i * 23)) $((220 + i * 20)) "$TMP/northern.jpg"
    i=$((i + 1))
done
i=1; for t in "Paper Moons" "Lanterns" "Kite Season" "Origami Heart"; do
    track "$M/Mira Sol/Paper Moons/0$i $t.mp3" "$t" "Mira Sol" "Paper Moons" - "$i/4" - 2021 Pop $((190 + i * 17)) $((300 + i * 25)) "$TMP/paper.jpg"
    i=$((i + 1))
done
i=1; for t in "Signal" "Neon Rain" "Low Battery" "Night Bus" "Static Bloom"; do
    track "$M/The Lantern Club/Static Bloom/0$i $t.mp3" "$t" "The Lantern Club" "Static Bloom" - "$i/5" - 2024 Electronic $((200 + i * 19)) $((180 + i * 30)) "$TMP/static.jpg"
    i=$((i + 1))
done
# Two discs, one folder each, the cover beside them as folder.jpg.
mkdir -p "$M/Harbour Choir/Harbour Songs"
cp "$TMP/harbour.jpg" "$M/Harbour Choir/Harbour Songs/folder.jpg"
for d in 1 2; do
    i=1; for t in "Tide" "Lighthouse" "Fog Bell"; do
        track "$M/Harbour Choir/Harbour Songs/CD$d/0$i $t $d.mp3" "$t ($d)" "Harbour Choir" "Harbour Songs" - "$i/3" "$d/2" 2019 Folk $((170 + i * 21 + d * 7)) $((260 + i * 15 + d * 10))
        i=$((i + 1))
    done
done
# A compilation: one album, several artists, no album artist tag.
k=1
for a in "Mira Sol|Sunday Drive" "Lumen Avenue|Open Road" "The Lantern Club|Coastline" "Ada Verne|Lemonade" "Harbour Choir|Boardwalk"; do
    artist=${a%%|*}; t=${a#*|}
    track "$M/Various/Summer Radio/0$k $artist - $t.mp3" "$t" "$artist" "Summer Radio" - "$k/5" - 2022 Pop $((185 + k * 13)) $((330 + k * 20)) "$TMP/summer.jpg"
    k=$((k + 1))
done
i=1; for t in "Greenhouse" "Ivy" "Glass Garden"; do
    track "$M/Ada Verne/Glass Garden/0$i $t.mp3" "$t" "Ada Verne" "Glass Garden" - "$i/3" - 2025 Jazz $((210 + i * 25)) $((240 + i * 35)) "$TMP/glass1.jpg"
    i=$((i + 1))
done
# Synced lyrics for the first song of Paper Moons.
cat > "$M/Mira Sol/Paper Moons/01 Paper Moons.lrc" <<'LRC'
[ar:Mira Sol]
[ti:Paper Moons]
[00:04.00]Folding the night into paper moons
[00:09.50]Hanging them up over your room
[00:15.00]Every crease a little light
[00:20.50]Every corner holding tight
[00:26.00]Paper moons, paper moons
[00:31.50]Shine for me tonight
[00:37.00]When the morning comes too soon
[00:42.50]Keep a little night in view
LRC
rm -rf "$TMP"
echo "$(find "$OUT" -name '*.mp3' | wc -l) songs in $OUT ($(du -sh "$OUT" | cut -f1))"
