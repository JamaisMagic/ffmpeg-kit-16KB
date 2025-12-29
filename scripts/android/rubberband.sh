#!/bin/bash

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# WORKAROUND TO DISABLE OPTIONAL FEATURES MANUALLY, SINCE ./configure DOES NOT PROVIDE OPTIONS FOR THEM
overwrite_file "${BASEDIR}"/tools/patch/make/rubberband/configure.ac "${BASEDIR}"/src/"${LIB_NAME}"/configure.ac || return 1
overwrite_file "${BASEDIR}"/tools/patch/make/rubberband/Makefile.android.in "${BASEDIR}"/src/"${LIB_NAME}"/Makefile.in || return 1

# WORKAROUND TO FIX PACKAGE CONFIG FILE DEPENDENCIES
overwrite_file "${BASEDIR}"/tools/patch/make/rubberband/rubberband.pc.in "${BASEDIR}"/src/"${LIB_NAME}"/rubberband.pc.in || return 1
${SED_INLINE} 's/%DEPENDENCIES%/sndfile, samplerate/g' "${BASEDIR}"/src/"${LIB_NAME}"/rubberband.pc.in || return 1

# ALWAYS REGENERATE BUILD FILES - NECESSARY TO APPLY THE WORKAROUNDS
autoreconf_library "${LIB_NAME}" 1>>"${BASEDIR}"/build.log 2>&1 || return 1

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --host="${HOST}" || return 1

# WORKAROUND FOR RUBBERBAND v3.0.0: DYNAMICALLY DETECT EXISTING SOURCE FILES
# Find all existing .cpp files in source directories and update Makefile
EXISTING_SOURCES=$(find src -name "*.cpp" -type f 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')

if [[ -n "${EXISTING_SOURCES}" ]]; then
  # Replace LIBRARY_SOURCES assignment with detected files
  # Use awk to find and replace the entire LIBRARY_SOURCES block
  awk -v sources="${EXISTING_SOURCES}" '
    BEGIN { in_library_sources = 0 }
    /^LIBRARY_SOURCES :=/ {
      in_library_sources = 1
      print "LIBRARY_SOURCES := " sources
      next
    }
    in_library_sources && /^[[:space:]]/ {
      # Skip continuation lines (lines starting with whitespace)
      next
    }
    in_library_sources {
      # Hit a non-continuation line, we're done with LIBRARY_SOURCES
      in_library_sources = 0
    }
    { print }
  ' Makefile > Makefile.tmp && mv Makefile.tmp Makefile || true
fi

make AR="$AR" -j$(get_cpu_count) || return 1

make install || return 1

# MANUALLY COPY PKG-CONFIG FILES
cp ./*.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
