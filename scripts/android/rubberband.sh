#!/bin/bash

# Run from library source (run-android.sh already does this; ensure it for v3)
cd "${BASEDIR}"/src/"${LIB_NAME}" || return 1

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null || true

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
  --host="${HOST}" 1>>"${BASEDIR}"/build.log 2>&1
CONFIGURE_EXIT=$?
if [[ ${CONFIGURE_EXIT} -ne 0 ]]; then
  echo -e "\n(*) rubberband configure failed (exit ${CONFIGURE_EXIT}). See build.log\n" 1>>"${BASEDIR}"/build.log 2>&1
  return 1
fi

# WORKAROUND FOR RUBBERBAND v3.0.0: DYNAMICALLY DETECT EXISTING SOURCE FILES
# Find all existing .cpp files in source directories and update Makefile.
# Exclude src/temporary.cpp: it is a dev stub that includes finer/R3StretcherImpl.h (not present in v3.0.0).
EXISTING_SOURCES=$(find src -name "*.cpp" -type f 2>/dev/null | grep -v '^src/temporary\.cpp$' | sort | tr '\n' ' ' | sed 's/ $//')

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
      # Hit a non-continuation line; we are done with LIBRARY_SOURCES
      in_library_sources = 0
    }
    { print }
  ' Makefile > Makefile.tmp && mv Makefile.tmp Makefile || true
fi

# WORKAROUND FOR RUBBERBAND v3: source uses src/common/ but includes expect system/
# (e.g. #include "system/sysutils.h"). Symlink src/system -> src/common so includes resolve.
if [[ -d src/common ]] && [[ ! -e src/system ]]; then
  ln -s common src/system
fi

# Build only the static library (v3.0.0 may have ladspa-lv2 instead of ladspa/, and we only need the lib)
mkdir -p lib bin
make AR="$AR" -j$(get_cpu_count) static 1>>"${BASEDIR}"/build.log 2>&1 || return 1

# Manual install: we did not build program/dynamic/ladspa, so do not run "make install"
mkdir -p "${LIB_INSTALL_PREFIX}"/lib "${LIB_INSTALL_PREFIX}"/include/rubberband || return 1
cp -f lib/librubberband.a "${LIB_INSTALL_PREFIX}"/lib/ || return 1
if [[ -d rubberband ]]; then
  for h in rubberband/rubberband-c.h rubberband/RubberBandStretcher.h; do
    [[ -f "$h" ]] && cp -f "$h" "${LIB_INSTALL_PREFIX}"/include/rubberband/
  done
  # If standard names missing, copy any headers present (v3 layout may differ)
  if [[ ! -f "${LIB_INSTALL_PREFIX}"/include/rubberband/RubberBandStretcher.h ]]; then
    cp -f rubberband/*.h "${LIB_INSTALL_PREFIX}"/include/rubberband/ 2>/dev/null || true
  fi
fi
# Generate and install .pc (PREFIX is already substituted in our .pc.in; fill at install time)
sed "s,%PREFIX%,${LIB_INSTALL_PREFIX},g" rubberband.pc.in | sed 's/%DEPENDENCIES%/sndfile, samplerate/g' > rubberband.pc
cp -f rubberband.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
