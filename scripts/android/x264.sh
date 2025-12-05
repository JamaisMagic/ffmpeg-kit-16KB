#!/bin/bash

# SET BUILD OPTIONS
ASM_OPTIONS=""
DEBUG_OPTIONS=""
case ${ARCH} in
x86)

  # please note that asm is disabled
  # enabling asm for x86 causes text relocations in libavfilter.so
  ASM_OPTIONS="--disable-asm"
  ;;
x86-64)
  if ! [ -x "$(command -v nasm)" ]; then
    echo -e "\n(*) nasm command not found\n"
    return 1
  fi

  export AS="$(command -v nasm)"

  # WORKAROUND TO ENABLE X86 ASM
  # https://github.com/android-ndk/ndk/issues/693
  export CFLAGS="${CFLAGS} -mno-stackrealign"
  ;;
esac
if [[ -n ${FFMPEG_KIT_DEBUG} ]]; then
  DEBUG_OPTIONS="--enable-debug"
fi

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# REGENERATE BUILD FILES IF NECESSARY OR REQUESTED
if [[ ! -f "${BASEDIR}"/src/"${LIB_NAME}"/configure ]] || [[ ${RECONF_x264} -eq 1 ]]; then
  autoreconf_library "${LIB_NAME}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --enable-pic \
  --sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-cli \
  ${ASM_OPTIONS} \
  ${DEBUG_OPTIONS} \
  --host="${HOST}" || return 1

# WORKAROUND TO FIX fseeko/ftello ERRORS WITH NDK r27
# x264's config.h defines fseek as fseeko and ftell as ftello,
# but these functions need _GNU_SOURCE or _POSIX_C_SOURCE to be declared.
# The issue is that config.h includes common/base.h which includes stdio.h,
# and _GNU_SOURCE must be defined before stdio.h is included.
# Since config.h is generated, we need to patch it to define _GNU_SOURCE
# at the very beginning, before any includes or other definitions.
if [[ -f "${BASEDIR}"/src/"${LIB_NAME}"/config.h ]]; then
  # Remove any existing _GNU_SOURCE define to avoid duplicates
  ${SED_INLINE} '/^#define _GNU_SOURCE/d' "${BASEDIR}"/src/"${LIB_NAME}"/config.h 2>/dev/null || true
  # Insert _GNU_SOURCE at the very first line of config.h, before everything else
  ${SED_INLINE} '1i\
#define _GNU_SOURCE\
' "${BASEDIR}"/src/"${LIB_NAME}"/config.h || return 1
fi
# Also patch common/base.h to ensure _GNU_SOURCE is defined before it includes stdio.h
if [[ -f "${BASEDIR}"/src/"${LIB_NAME}"/common/base.h ]]; then
  # Remove any existing _GNU_SOURCE define to avoid duplicates
  ${SED_INLINE} '/^#define _GNU_SOURCE/d' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.h 2>/dev/null || true
  # Insert _GNU_SOURCE before the first #include
  if grep -qE '^#include' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.h 2>/dev/null; then
    ${SED_INLINE} '/^#include/i\
#define _GNU_SOURCE\
' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.h || return 1
  else
    # If no includes found, insert at the beginning
    ${SED_INLINE} '1i\
#define _GNU_SOURCE\
' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.h || return 1
  fi
fi
# Also ensure common/base.c has _GNU_SOURCE before it includes config.h
if [[ -f "${BASEDIR}"/src/"${LIB_NAME}"/common/base.c ]]; then
  # Remove any existing _GNU_SOURCE define to avoid duplicates
  ${SED_INLINE} '/^#define _GNU_SOURCE/d' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.c 2>/dev/null || true
  # Insert _GNU_SOURCE at the very first line, before any includes
  ${SED_INLINE} '1i\
#define _GNU_SOURCE\
' "${BASEDIR}"/src/"${LIB_NAME}"/common/base.c || return 1
fi

make -j$(get_cpu_count) || return 1

make install || return 1

# MANUALLY COPY PKG-CONFIG FILES
cp x264.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
