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

# MANUALLY COPY PKG-CONFIG FILES (so FFmpeg's pkg-config finds sdl2)
if ls ./*.pc 1>/dev/null 2>&1; then
  cp ./*.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
fi
if [[ ! -f "${INSTALL_PKG_CONFIG_DIR}/sdl2.pc" ]] && [[ -f "${LIB_INSTALL_PREFIX}/lib/pkgconfig/sdl2.pc" ]]; then
  cp "${LIB_INSTALL_PREFIX}/lib/pkgconfig/sdl2.pc" "${INSTALL_PKG_CONFIG_DIR}/" || return 1
  echo -e "INFO: Copied sdl2.pc from install prefix to ${INSTALL_PKG_CONFIG_DIR}\n" 1>>"${BASEDIR}"/build.log 2>&1
fi
if [[ ! -f "${INSTALL_PKG_CONFIG_DIR}/sdl2.pc" ]]; then
  echo -e "\nWARN: sdl2.pc was not found after SDL build; FFmpeg may fail or build without sdl2.\n" 1>>"${BASEDIR}"/build.log 2>&1
fi
