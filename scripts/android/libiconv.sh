#!/bin/bash

# FIX HARD-CODED PATHS
${SED_INLINE} 's|git://git.savannah.gnu.org|https://github.com/arthenica|g' "${BASEDIR}"/src/"${LIB_NAME}"/.gitmodules || return 1

# libiconv's build tooling looks for versioned Automake binaries (aclocal-1.17,
# automake-1.17). GitHub runners only ship 1.16 today, so create shims pointing
# to the available tools to avoid "aclocal-1.17: not found" failures.
mkdir -p "${BASEDIR}"/.tmp
ln -s -f "$(which aclocal)" "${BASEDIR}"/.tmp/aclocal-1.16
ln -s -f "$(which automake)" "${BASEDIR}"/.tmp/automake-1.16
ln -s -f "$(which aclocal)" "${BASEDIR}"/.tmp/aclocal-1.17
ln -s -f "$(which automake)" "${BASEDIR}"/.tmp/automake-1.17
PATH="${BASEDIR}/.tmp":$PATH

# Use a native compiler for build-time generators (e.g., genaliases) to avoid
# executing cross-compiled ARM binaries on the host.
if command -v clang >/dev/null 2>&1; then
  export CC_FOR_BUILD="$(command -v clang)"
elif command -v gcc >/dev/null 2>&1; then
  export CC_FOR_BUILD="$(command -v gcc)"
else
  export CC_FOR_BUILD="$(command -v cc)"
fi
if [[ ! -d "${BASEDIR}"/src/"${LIB_NAME}"/gnulib ]]; then

  # INIT SUBMODULES
  ./gitsub.sh pull || return 1
  ./gitsub.sh checkout gnulib 485d983b7795548fb32b12fbe8370d40789e88c4 || return 1
fi

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# REGENERATE BUILD FILES IF NECESSARY OR REQUESTED
if [[ ! -f "${BASEDIR}"/src/"${LIB_NAME}"/configure ]] || [[ ${RECONF_libiconv} -eq 1 ]]; then
  ./autogen.sh || return 1
fi

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --with-pic \
  --with-sysroot="${ANDROID_SYSROOT}" \
  --enable-static \
  --disable-shared \
  --disable-fast-install \
  --disable-rpath \
  --host="${HOST}" || return 1

# Prebuild the genaliases generator with the host compiler so make does not
# attempt to build (and execute) a cross-compiled binary.
pushd "${BASEDIR}/src/${LIB_NAME}" >/dev/null || return 1
"${CC_FOR_BUILD}" lib/genaliases.c -o genaliases || { popd >/dev/null; return 1; }
popd >/dev/null || return 1

make -j$(get_cpu_count) || return 1

make install || return 1

# CREATE PACKAGE CONFIG MANUALLY
create_libiconv_package_config "1.18" || return 1
