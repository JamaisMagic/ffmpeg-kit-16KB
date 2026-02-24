#!/bin/bash

# util-linux uses a top-level build system
# We need to configure and build from the root, but only build libuuid
cd "${BASEDIR}"/src/"${LIB_NAME}" || return 1

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# REGENERATE BUILD FILES IF NECESSARY OR REQUESTED
if [[ ! -f "${BASEDIR}"/src/"${LIB_NAME}"/configure ]] || [[ ${RECONF_libuuid} -eq 1 ]]; then
  autoreconf_library "${LIB_NAME}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1
fi

# Configure util-linux
# libuuid is built by default, we'll only build that component
# util-linux enforces 64-bit time_t by default. Android armv7 toolchains can fail
# this check, so disable the year2038 requirement only for 32-bit ARM targets.
YEAR2038_OPTION=""
if [[ "${ARCH}" == "arm-v7a" ]] || [[ "${ARCH}" == "arm-v7a-neon" ]]; then
  YEAR2038_OPTION="--disable-year2038"
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --with-pic \
  --with-sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-shared \
  --disable-liblastlog2 \
  --disable-libblkid \
  --disable-libmount \
  --disable-libsmartcols \
  --disable-libfdisk \
  --disable-libfstrim \
  --disable-fast-install \
  ${YEAR2038_OPTION} \
  --host="${HOST}" 1>>"${BASEDIR}"/build.log 2>&1
CONFIGURE_EXIT=$?
if [[ ${CONFIGURE_EXIT} -ne 0 ]]; then
  echo -e "\n(*) libuuid(util-linux) configure failed (exit ${CONFIGURE_EXIT}). Dumping config.log:\n" 1>>"${BASEDIR}"/build.log 2>&1
  if [[ -f config.log ]]; then
    cat config.log 1>>"${BASEDIR}"/build.log 2>&1
  fi
  return 1
fi

# Build only libuuid
make -j$(get_cpu_count) -C libuuid || return 1

# Install libuuid manually since we're only building that component
mkdir -p "${LIB_INSTALL_PREFIX}"/lib || return 1
mkdir -p "${LIB_INSTALL_PREFIX}"/include || return 1

# Copy the library file (check both .libs and direct location)
if [[ -f libuuid/.libs/libuuid.a ]]; then
  cp libuuid/.libs/libuuid.a "${LIB_INSTALL_PREFIX}"/lib/ || return 1
elif [[ -f libuuid/libuuid.a ]]; then
  cp libuuid/libuuid.a "${LIB_INSTALL_PREFIX}"/lib/ || return 1
else
  echo -e "ERROR: libuuid.a not found after build\n" 1>>"${BASEDIR}"/build.log 2>&1
  return 1
fi

# Copy the header file
if [[ -f libuuid/uuid.h ]]; then
  cp libuuid/uuid.h "${LIB_INSTALL_PREFIX}"/include/ || return 1
else
  echo -e "ERROR: uuid.h not found\n" 1>>"${BASEDIR}"/build.log 2>&1
  return 1
fi

# CREATE PACKAGE CONFIG MANUALLY
# Get version from util-linux's configure.ac
UUID_VERSION=$(grep '^AC_INIT' configure.ac 2>/dev/null | sed -E 's/.*\[([0-9]+\.[0-9]+)\].*/\1/' 2>/dev/null || echo "2.40")
create_uuid_package_config "${UUID_VERSION}" || return 1
