#!/bin/sh
# Builds the plugin (and on x86-64 the unit tests) six ways - GCC and Clang
# for armv7, aarch64 and x86-64 - with extra warnings, and fails on any
# warning in the app's own code.
#
#   tests/build-matrix.sh <build TMPDIR> <Qt host dir> <work dir>
#
# Everything comes from the LuneOS build's sysroots-components: the target
# sysroots are put together by tests/host-sysroot.sh (cortexa8t2hf-neon-halium,
# aarch64, corei7-64), the cross GCCs from gcc-cross-* and binutils-cross-*
# with the native libraries they load. Clang is the build host's, pointed
# at the same sysroots. The Qt host dir is qtbase-native and friends (moc
# must match the target Qt).
set -e
cd "$(dirname "$0")/.."
TMPD=${1:?usage: build-matrix.sh <build TMPDIR> <Qt host dir> <work dir>}
QTHOST=$(cd "${2:?}" && pwd)
WORK=${3:?}
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
SRC=$(pwd)
SC=$TMPD/sysroots-components
WARN="-Wall -Wextra -Wpedantic -Wshadow -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Wformat=2"
FAILED=$WORK/failed
rm -f "$FAILED"

# The cross compilers: gcc-cross and binutils-cross, and the native gmp,
# mpfr, mpc, zlib and zstd cc1plus is linked against.
toolchain() {   # arch(arm|aarch64)
    dir=$WORK/xtool-$1
    if [ ! -x "$dir/usr/bin" ]; then
        mkdir -p "$dir"
        # tar, not cp: the components hard-link files between them.
        for c in gcc-cross-$1 binutils-cross-$1 gmp-native mpfr-native libmpc-native zlib-native zstd-native; do
            tar -C "$SC/x86_64/$c" -cf - . | tar -C "$dir" -xf -
        done
        rm -rf "$dir/sysroot-providers"
    fi
    echo "$dir"
}

sysroot() {   # component arch
    dir=$WORK/sysroot-$1
    if [ ! -d "$dir/usr/include" ]; then
        mkdir -p "$dir"
        tests/host-sysroot.sh "$TMPD" "$dir" "$1" > /dev/null
    fi
    echo "$dir"
}

build() {   # name cmake-args...
    name=$1; shift
    dir=$WORK/$name
    rm -rf "$dir"
    if ! cmake -S "$SRC" -B "$dir" -G Ninja -DCMAKE_BUILD_TYPE=Release "$@" > "$dir.cmake.log" 2>&1; then
        echo "$name: configure FAILED (see $dir.cmake.log)"; touch "$FAILED"; return
    fi
    if ! ninja -C "$dir" > "$dir.log" 2>&1; then
        echo "$name: build FAILED (see $dir.log)"; touch "$FAILED"; return
    fi
    # Warnings from the app's own files; Qt's and TagLib's headers apart.
    own=$(grep -E "warning:" "$dir.log" | grep -E "$SRC/(MusicApp|tests)/" | sort -u | wc -l)
    other=$(grep -E "warning:" "$dir.log" | grep -v -E "$SRC/(MusicApp|tests)/" | sort -u | wc -l)
    echo "$name: built, $own warnings in our code, $other elsewhere"
    [ "$own" -eq 0 ] || touch "$FAILED"
}

# Clang has no idea of Yocto's layout: the GCC runtime (crtbeginS.o,
# libgcc) is in usr/lib/<triple>/<version>, libstdc++'s headers in
# usr/include/c++/<version>.
clang_flags() {   # sysroot triple
    gcclib=$(dirname "$(find "$1/usr/lib" -name crtbeginS.o | head -n 1)")
    ver=$(basename "$gcclib")
    echo "-B$gcclib -isystem $1/usr/include/c++/$ver -isystem $1/usr/include/c++/$ver/$2"
}

clang_ldflags() {   # sysroot [linker]
    gcclib=$(dirname "$(find "$1/usr/lib" -name crtbeginS.o | head -n 1)")
    echo "-L$gcclib${2:+ --ld-path=$2}"
}

pkgconfig_env() {   # sysroot
    echo "PKG_CONFIG_SYSROOT_DIR=$1 PKG_CONFIG_LIBDIR=$1/usr/lib/pkgconfig:$1/usr/share/pkgconfig"
}

for arch in arm aarch64; do
  (
    if [ $arch = arm ]; then
        # The halium armv7 components: the plain cortexa8t2hf-neon ones
        # are half staged (no Qt Qml) in this build.
        S=$(sysroot cortexa8t2hf-neon-halium); triple=arm-webos-linux-gnueabi
        # Qt Gui wants EGL and GLES, which halium gets from libhybris: a
        # machine's (the TouchPad's, armv7 halium).
        for c in libhybris android-headers-halium; do
            [ -d "$S/usr/include/hybris" ] || tar -C "$SC/tenderloin_halium/$c" -cf - . | tar -C "$S" -xf -
        done
        cpu="-mthumb -mfpu=neon -mfloat-abi=hard -mcpu=cortex-a8"
    else
        S=$(sysroot aarch64); triple=aarch64-webos-linux; cpu=""
    fi
    T=$(toolchain $arch)
    PATH=$T/usr/bin/$triple:$T/usr/bin:$PATH
    LD_LIBRARY_PATH=$T/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    export PATH LD_LIBRARY_PATH
    export $(pkgconfig_env "$S")
    build "$arch-gcc" -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" \
        -DTEST_SYSROOT="$S" -DQT_HOST_PATH="$QTHOST/usr" \
        -DCMAKE_C_COMPILER="$triple-gcc" -DCMAKE_CXX_COMPILER="$triple-g++" \
        -DCMAKE_CXX_FLAGS="$cpu --sysroot=$S $WARN" -DCMAKE_C_FLAGS="$cpu --sysroot=$S"
    flags=$(clang_flags "$S" "$triple")
    ld=$(clang_ldflags "$S" "$T/usr/bin/$triple/$triple-ld")
    build "$arch-clang" -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" \
        -DTEST_SYSROOT="$S" -DTEST_TARGET="$triple" -DQT_HOST_PATH="$QTHOST/usr" \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_CXX_FLAGS="$cpu $flags $WARN" -DCMAKE_C_FLAGS="$cpu $flags" \
        -DCMAKE_SHARED_LINKER_FLAGS="$ld" -DCMAKE_MODULE_LINKER_FLAGS="$ld" -DCMAKE_EXE_LINKER_FLAGS="$ld"
  )
done

X=$(sysroot corei7-64)
for cc in gcc clang; do
  (
    export $(pkgconfig_env "$X")
    cxx=$([ $cc = gcc ] && echo g++ || echo clang++)
    extra=""
    ld=""
    if [ $cc = clang ]; then extra=$(clang_flags "$X" x86_64-webos-linux); ld=$(clang_ldflags "$X"); fi
    build "x86_64-$cc" -DBUILD_TESTING=ON -DCMAKE_TOOLCHAIN_FILE="$SRC/tests/host-toolchain.cmake" \
        -DTEST_SYSROOT="$X" -DQT_HOST_PATH="$QTHOST/usr" \
        -DCMAKE_C_COMPILER=$cc -DCMAKE_CXX_COMPILER=$cxx -DCMAKE_CXX_FLAGS="$extra $WARN" -DCMAKE_C_FLAGS="$extra" \
        -DCMAKE_SHARED_LINKER_FLAGS="$ld" -DCMAKE_MODULE_LINKER_FLAGS="$ld" -DCMAKE_EXE_LINKER_FLAGS="$ld"
  )
done

[ ! -e "$FAILED" ]
