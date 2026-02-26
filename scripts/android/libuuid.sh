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
if [[ "${ARCH}" == "arm-v7a" ]] || [[ "${ARCH}" == "arm-v7a-neon" ]] || [[ "${ARCH}" == "x86" ]]; then
  YEAR2038_OPTION="--disable-year2038"
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --with-pic \
  --with-sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-shared \
  --disable-nls \
  --disable-asciidoc \
  --disable-manpages \
  --disable-all-programs \
  --disable-liblastlog2 \
  --disable-libblkid \
  --disable-libmount \
  --disable-libsmartcols \
  --disable-libfdisk \
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

# Build libuuid from util-linux top-level Makefile.
# Target "libuuid" is a no-op (directory name). The real library target is "libuuid.la" (usrlib_exec_LTLIBRARIES).
# Try "make libuuid.la" first; if that does not create the archive, run default "make" to build enabled targets.
echo -e "INFO: libuuid build working directory: $(pwd)\n" 1>>"${BASEDIR}"/build.log 2>&1
make -j$(get_cpu_count) libuuid.la 1>>"${BASEDIR}"/build.log 2>&1 || return 1
echo -e "INFO: libuuid compile step completed. Verifying generated artifacts...\n" 1>>"${BASEDIR}"/build.log 2>&1

# Install libuuid manually since we're only building that component
mkdir -p "${LIB_INSTALL_PREFIX}"/lib || return 1
mkdir -p "${LIB_INSTALL_PREFIX}"/include || return 1

# Copy the library file (util-linux builds libuuid.la in top-level; libtool puts .a in .libs/)
LIBUUID_ARCHIVE_PATH=""
if [[ -f .libs/libuuid.a ]]; then
  LIBUUID_ARCHIVE_PATH=".libs/libuuid.a"
elif [[ -f libuuid/.libs/libuuid.a ]]; then
  LIBUUID_ARCHIVE_PATH="libuuid/.libs/libuuid.a"
elif [[ -f libuuid/libuuid.a ]]; then
  LIBUUID_ARCHIVE_PATH="libuuid/libuuid.a"
elif [[ -f libuuid/src/.libs/libuuid.a ]]; then
  LIBUUID_ARCHIVE_PATH="libuuid/src/.libs/libuuid.a"
elif [[ -f libuuid/src/libuuid.a ]]; then
  LIBUUID_ARCHIVE_PATH="libuuid/src/libuuid.a"
fi

if [[ -n "${LIBUUID_ARCHIVE_PATH}" ]]; then
  echo -e "INFO: libuuid static library path: ${BASEDIR}/src/${LIB_NAME}/${LIBUUID_ARCHIVE_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1
  cp "${LIBUUID_ARCHIVE_PATH}" "${LIB_INSTALL_PREFIX}"/lib/ || return 1
else
  echo -e "ERROR: libuuid.a not found after build\n" 1>>"${BASEDIR}"/build.log 2>&1
  echo -e "INFO: Debug listing of candidate libuuid output directories:\n" 1>>"${BASEDIR}"/build.log 2>&1
  echo -e "INFO: ls -la .libs (top-level)\n" 1>>"${BASEDIR}"/build.log 2>&1
  ls -la .libs 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: ls -la libuuid\n" 1>>"${BASEDIR}"/build.log 2>&1
  ls -la libuuid 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: ls -la libuuid/.libs\n" 1>>"${BASEDIR}"/build.log 2>&1
  ls -la libuuid/.libs 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: ls -la libuuid/src\n" 1>>"${BASEDIR}"/build.log 2>&1
  ls -la libuuid/src 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: ls -la libuuid/src/.libs\n" 1>>"${BASEDIR}"/build.log 2>&1
  ls -la libuuid/src/.libs 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: search for files named '*uuid*.a':\n" 1>>"${BASEDIR}"/build.log 2>&1
  find . -maxdepth 4 -type f -name "*uuid*.a" 1>>"${BASEDIR}"/build.log 2>&1 || true
  echo -e "INFO: search for files named 'uuid.h' under libuuid:\n" 1>>"${BASEDIR}"/build.log 2>&1
  find libuuid -type f -name "uuid.h" 1>>"${BASEDIR}"/build.log 2>&1 || true
  return 1
fi

# Copy the header file
LIBUUID_HEADER_PATH=""
if [[ -f libuuid/uuid.h ]]; then
  LIBUUID_HEADER_PATH="libuuid/uuid.h"
elif [[ -f libuuid/src/uuid.h ]]; then
  LIBUUID_HEADER_PATH="libuuid/src/uuid.h"
fi

if [[ -n "${LIBUUID_HEADER_PATH}" ]]; then
  echo -e "INFO: libuuid header path: ${BASEDIR}/src/${LIB_NAME}/${LIBUUID_HEADER_PATH}\n" 1>>"${BASEDIR}"/build.log 2>&1
  cp "${LIBUUID_HEADER_PATH}" "${LIB_INSTALL_PREFIX}"/include/ || return 1
else
  echo -e "ERROR: uuid.h not found\n" 1>>"${BASEDIR}"/build.log 2>&1
  return 1
fi

echo -e "INFO: libuuid artifacts copied successfully to ${LIB_INSTALL_PREFIX}\n" 1>>"${BASEDIR}"/build.log 2>&1

# CREATE PACKAGE CONFIG MANUALLY
# Get version from util-linux's configure.ac
UUID_VERSION=$(grep '^AC_INIT' configure.ac 2>/dev/null | sed -E 's/.*\[([0-9]+\.[0-9]+)\].*/\1/' 2>/dev/null || echo "2.40")
create_uuid_package_config "${UUID_VERSION}" || return 1
