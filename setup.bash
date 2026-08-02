set -e

export DEVKITPRO=/opt/devkitpro
export RENPY_VER=7.6.3
export PYGAME_SDL2_VER=2.1.0

apt-get -y update
apt-get -y upgrade

apt-get -y install build-essential checkinstall wget
apt-get -y install libncurses-dev libssl-dev libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev zlib1g-dev libreadline-dev libffi-dev

if ! command -v python2 >/dev/null 2>&1; then
  echo "Building Python 2.7.18 from source..."
  wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tar.xz
  tar -xf Python-2.7.18.tar.xz
  pushd Python-2.7.18
  ./configure --enable-shared --prefix=/usr
  make -j$(nproc)
  make install
  popd
  rm -rf Python-2.7.18 Python-2.7.18.tar.xz
  ldconfig
fi

python2 --version

curl https://bootstrap.pypa.io/pip/2.7/get-pip.py --output get-pip.py
python2 get-pip.py
pip2 --version 

apt-get -y install p7zip-full libsdl2-dev libsdl2-image-dev libjpeg-dev libpng-dev libsdl2-ttf-dev libsdl2-mixer-dev libavformat-dev libfreetype6-dev libswscale-dev libglew-dev libfribidi-dev libavcodec-dev libswresample-dev libsdl2-gfx-dev libgl1
pip2 uninstall -y distribute || true
pip2 install future six typing requests ecdsa pefile==2019.4.18 Cython==0.29.36 setuptools==0.9.8

curl -LOC - https://github.com/knautilus/Utils/releases/download/v1.0/devkitpro-pkgbuild-helpers-2.2.4-2-any.pkg.tar.xz
curl -LOC - https://github.com/knautilus/Utils/releases/download/v1.0/python27-switch.zip
curl -LOC - https://github.com/knautilus/Utils/releases/download/v1.0/switch-libfribidi-1.0.12-1-any.pkg.tar.xz
dkp-pacman -Rdd --noconfirm dkp-meson-scripts dkp-toolchain-vars || true
dkp-pacman -U --noconfirm devkitpro-pkgbuild-helpers-2.2.4-2-any.pkg.tar.xz
dkp-pacman -U --noconfirm switch-libfribidi-1.0.12-1-any.pkg.tar.xz
unzip -qq python27-switch.zip -d $DEVKITPRO/portlibs/switch

rm devkitpro-pkgbuild-helpers-2.2.4-2-any.pkg.tar.xz
rm switch-libfribidi-1.0.12-1-any.pkg.tar.xz
rm python27-switch.zip

/bin/bash -c 'sed -i'"'"'.bak'"'"' '"'"'s/set(CMAKE_EXE_LINKER_FLAGS_INIT "/set(CMAKE_EXE_LINKER_FLAGS_INIT "-fPIC /'"'"' $DEVKITPRO/switch.cmake'


curl -LOC - https://www.renpy.org/dl/$RENPY_VER/pygame_sdl2-$PYGAME_SDL2_VER+renpy$RENPY_VER.tar.gz
curl -LOC - https://www.renpy.org/dl/$RENPY_VER/renpy-$RENPY_VER-sdk.zip
curl -LOC - https://www.renpy.org/dl/$RENPY_VER/renpy-$RENPY_VER-source.tar.bz2
#curl -LOC - https://www.renpy.org/dl/$RENPY_VER/android-native-symbols.zip
#curl -LOC - https://dl.otorh.in/github/rawproject.zip

rm -rf pygame_sdl2-$PYGAME_SDL2_VER+renpy$RENPY_VER pygame_sdl2-source
tar -xf pygame_sdl2-$PYGAME_SDL2_VER+renpy$RENPY_VER.tar.gz
mv pygame_sdl2-$PYGAME_SDL2_VER+renpy$RENPY_VER pygame_sdl2-source
rm pygame_sdl2-$PYGAME_SDL2_VER+renpy$RENPY_VER.tar.gz

rm -rf renpy-$RENPY_VER-source renpy-source
tar -xf renpy-$RENPY_VER-source.tar.bz2
mv renpy-$RENPY_VER-source renpy-source
rm renpy-$RENPY_VER-source.tar.bz2

rm -rf renpy-$RENPY_VER-sdk renpy_sdk
unzip -qq renpy-$RENPY_VER-sdk.zip -d renpy_sdk
rm renpy-$RENPY_VER-sdk.zip
cp -rf subprocess.pyo renpy_sdk/renpy-$RENPY_VER-sdk/lib/python2.7

#dkp-pacman --noconfirm -S switch-libfribidi

#rm -rf raw
#unzip -qq rawproject.zip -d raw
#rm rawproject.zip

#rm -rf android-native-symbols renpy_androidlib ./raw/android/lib
#unzip -qq android-native-symbols.zip -d ./raw/android/lib
#rm -rf ./raw/android/lib/x86_64/
#rm android-native-symbols.zip

pushd renpy-source
patch -p1 < ../renpy.patch

# Apply FFmpeg 5+/6+ compatibility fix to module/ffmedia.c
cat << 'EOF' > fix_ffmedia.py
with open('module/ffmedia.c', 'r') as f:
    code = f.read()

header_fix = '''#include <stdlib.h>

#if LIBAVUTIL_VERSION_INT >= AV_VERSION_INT(57, 28, 100)
#define RWOPS_BUF_CONST const
static inline struct SwrContext *renpy_swr_alloc_set_opts(struct SwrContext *s, uint64_t out_ch_layout, enum AVSampleFormat out_sample_fmt, int out_sample_rate, uint64_t in_ch_layout, enum AVSampleFormat in_sample_fmt, int in_sample_rate, int log_offset, void *log_ctx) {
    AVChannelLayout out_layout, in_layout;
    struct SwrContext *ctx = s;
    av_channel_layout_from_mask(&out_layout, out_ch_layout);
    av_channel_layout_from_mask(&in_layout, in_ch_layout);
    swr_alloc_set_opts2(&ctx, &out_layout, out_sample_fmt, out_sample_rate, &in_layout, in_sample_fmt, in_sample_rate, log_offset, log_ctx);
    return ctx;
}
#define swr_alloc_set_opts renpy_swr_alloc_set_opts
#define renpy_get_channel_layout(frame) ((frame)->ch_layout.u.mask)
#define renpy_get_channels(frame) ((frame)->ch_layout.nb_channels)
#else
#define RWOPS_BUF_CONST
#define renpy_get_channel_layout(frame) ((frame)->channel_layout)
#define renpy_get_channels(frame) ((frame)->channels)
#endif
'''

code = code.replace('#include <stdlib.h>', header_fix, 1)

code = code.replace(
    'static int rwops_write(void *opaque, uint8_t *buf, int buf_size)',
    'static int rwops_write(void *opaque, RWOPS_BUF_CONST uint8_t *buf, int buf_size)'
)

old_stereo = 'converted_frame->channel_layout = AV_CH_LAYOUT_STEREO;'
new_stereo = '''#if LIBAVUTIL_VERSION_INT >= AV_VERSION_INT(57, 28, 100)
            av_channel_layout_default(&converted_frame->ch_layout, 2);
#else
            converted_frame->channel_layout = AV_CH_LAYOUT_STEREO;
#endif'''
code = code.replace(old_stereo, new_stereo)

old_layout_init = 'ms->audio_decode_frame->channel_layout = av_get_default_channel_layout(ms->audio_decode_frame->channels);'
new_layout_init = '''#if LIBAVUTIL_VERSION_INT >= AV_VERSION_INT(57, 28, 100)
                                av_channel_layout_default(&ms->audio_decode_frame->ch_layout, ms->audio_decode_frame->ch_layout.nb_channels);
#else
                                ms->audio_decode_frame->channel_layout = av_get_default_channel_layout(ms->audio_decode_frame->channels);
#endif'''
code = code.replace(old_layout_init, new_layout_init)

code = code.replace('!ms->audio_decode_frame->channel_layout', '!renpy_get_channel_layout(ms->audio_decode_frame)')

code = code.replace('ms->audio_decode_frame->channels == 1', 'renpy_get_channels(ms->audio_decode_frame) == 1')
code = code.replace('converted_frame->channel_layout,', 'renpy_get_channel_layout(converted_frame),')
code = code.replace('ms->audio_decode_frame->channel_layout,', 'renpy_get_channel_layout(ms->audio_decode_frame),')

with open('module/ffmedia.c', 'w') as f:
    f.write(code)

EOF
python2 fix_ffmedia.py && rm fix_ffmedia.py

pushd module
rm -rf gen gen-static
popd
popd
pushd pygame_sdl2-source
rm -rf gen gen-static
popd
