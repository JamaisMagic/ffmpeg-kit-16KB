#!/bin/bash

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# REGENERATE BUILD FILES IF NECESSARY OR REQUESTED
if [[ ! -f "${BASEDIR}"/src/"${LIB_NAME}"/configure ]] || [[ ${RECONF_sdl} -eq 1 ]]; then
  autoreconf_library "${LIB_NAME}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --with-pic \
  --without-x \
  --with-sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-shared \
  --disable-fast-install \
  --host="${HOST}" || return 1

make -j$(get_cpu_count) || return 1

make install || return 1

# Copy sdl2.pc to the shared pkgconfig dir so FFmpeg's configure finds it (PKG_CONFIG_PATH points there).
# make install puts it in ${LIB_INSTALL_PREFIX}/lib/pkgconfig; we need it in ${INSTALL_PKG_CONFIG_DIR}.
SDL_PC_SRC="${LIB_INSTALL_PREFIX}/lib/pkgconfig/sdl2.pc"
SDL_PC_DST="${INSTALL_PKG_CONFIG_DIR}/sdl2.pc"
echo -e "DEBUG: SDL pkg-config: INSTALL_PKG_CONFIG_DIR=${INSTALL_PKG_CONFIG_DIR}\n" 1>>"${BASEDIR}"/build.log 2>&1
if [[ -f "${SDL_PC_SRC}" ]]; then
  mkdir -p "${INSTALL_PKG_CONFIG_DIR}" 1>>"${BASEDIR}"/build.log 2>&1
  cp "${SDL_PC_SRC}" "${SDL_PC_DST}" || return 1
  echo -e "INFO: Copied sdl2.pc to ${INSTALL_PKG_CONFIG_DIR}\n" 1>>"${BASEDIR}"/build.log 2>&1
else
  if ls ./*.pc 1>/dev/null 2>&1; then
    cp ./*.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
    echo -e "INFO: Copied ./*.pc (build dir) to ${INSTALL_PKG_CONFIG_DIR}\n" 1>>"${BASEDIR}"/build.log 2>&1
  else
    echo -e "\nWARN: sdl2.pc not found at ${SDL_PC_SRC} and no .pc in build dir; FFmpeg may fail or build without sdl2.\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
fi
if [[ ! -f "${SDL_PC_DST}" ]]; then
  echo -e "\nWARN: sdl2.pc still missing at ${SDL_PC_DST}\n" 1>>"${BASEDIR}"/build.log 2>&1
fi
