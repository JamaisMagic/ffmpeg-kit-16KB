#!/bin/bash

# util-linux stores libuuid in a subdirectory
# Change to the libuuid subdirectory for building
cd "${BASEDIR}"/src/"${LIB_NAME}"/libuuid || return 1

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# REGENERATE BUILD FILES IF NECESSARY OR REQUESTED
if [[ ! -f "${BASEDIR}"/src/"${LIB_NAME}"/libuuid/configure ]] || [[ ${RECONF_libuuid} -eq 1 ]]; then
  # Run autoreconf in the current directory (libuuid subdirectory)
  autoreconf --force --install 2>>"${BASEDIR}"/build.log 1>>"${BASEDIR}"/build.log || \
  autoreconf --force --install -I m4 2>>"${BASEDIR}"/build.log 1>>"${BASEDIR}"/build.log || \
  autoreconf --install 2>>"${BASEDIR}"/build.log 1>>"${BASEDIR}"/build.log || \
  autoreconf 2>>"${BASEDIR}"/build.log 1>>"${BASEDIR}"/build.log || return 1
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --with-pic \
  --with-sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-shared \
  --disable-fast-install \
  --host="${HOST}" || return 1

make -j$(get_cpu_count) || return 1

make install || return 1

# CREATE PACKAGE CONFIG MANUALLY
# Get version from util-linux (libuuid version is typically the same as util-linux version)
# Try to extract version from configure.ac or use a default
UUID_VERSION=$(grep '^AC_INIT' configure.ac 2>/dev/null | sed -E 's/.*\[([0-9]+\.[0-9]+)\].*/\1/' 2>/dev/null || echo "2.40")
create_uuid_package_config "${UUID_VERSION}" || return 1
