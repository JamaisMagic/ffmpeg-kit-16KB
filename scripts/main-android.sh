#!/bin/bash

if [[ -z ${ARCH} ]]; then
  echo -e "\n(*) ARCH not defined\n"
  exit 1
fi

if [[ -z ${API} ]]; then
  echo -e "\n(*) API not defined\n"
  exit 1
fi

if [[ -z ${BASEDIR} ]]; then
  echo -e "\n(*) BASEDIR not defined\n"
  exit 1
fi

if [[ -z ${TOOLCHAIN} ]]; then
  echo -e "\n(*) TOOLCHAIN not defined\n"
  exit 1
fi

if [[ -z ${TOOLCHAIN_ARCH} ]]; then
  echo -e "\n(*) TOOLCHAIN_ARCH not defined\n"
  exit 1
fi

echo -e "\nBuilding ${ARCH} platform on API level ${API}\n"
echo -e "\nINFO: Starting new build for ${ARCH} on API level ${API} at $(date)\n" 1>>"${BASEDIR}"/build.log 2>&1

# SET BASE INSTALLATION DIRECTORY FOR THIS ARCHITECTURE
export LIB_INSTALL_BASE="${BASEDIR}/prebuilt/$(get_build_directory)"

# CREATE PACKAGE CONFIG DIRECTORY FOR THIS ARCHITECTURE
PKG_CONFIG_DIRECTORY="${LIB_INSTALL_BASE}/pkgconfig"
if [ ! -d "${PKG_CONFIG_DIRECTORY}" ]; then
  mkdir -p "${PKG_CONFIG_DIRECTORY}" || return 1
fi

# FILTER WHICH EXTERNAL LIBRARIES WILL BE BUILT
# NOTE THAT BUILT-IN LIBRARIES ARE FORWARDED TO FFMPEG SCRIPT WITHOUT ANY PROCESSING
enabled_library_list=()
for library in {1..50}; do
  if [[ ${!library} -eq 1 ]]; then
    ENABLED_LIBRARY=$(get_library_name $((library - 1)))
    enabled_library_list+=(${ENABLED_LIBRARY})

    echo -e "INFO: Enabled library ${ENABLED_LIBRARY} will be built\n" 1>>"${BASEDIR}"/build.log 2>&1
  fi
done

# Helper function to check if a library is in the enabled list
is_library_enabled() {
  local lib_name=$1
  for enabled_lib in "${enabled_library_list[@]}"; do
    if [[ "$enabled_lib" == "$lib_name" ]]; then
      return 0
    fi
  done
  return 1
}

# BUILD LTS SUPPORT LIBRARY FOR API < 18
if [[ -n ${FFMPEG_KIT_LTS_BUILD} ]] && [[ ${API} -lt 18 ]]; then
  build_android_lts_support
fi

# BUILD ENABLED LIBRARIES AND THEIR DEPENDENCIES
let completed=0
let previous_completed=0
let no_progress_iterations=0
while [ ${#enabled_library_list[@]} -gt $completed ]; do
  for library in "${enabled_library_list[@]}"; do
    let run=0
    case $library in
    fontconfig)
      if [[ $OK_libuuid -eq 1 ]] && [[ $OK_expat -eq 1 ]] && [[ $OK_libiconv -eq 1 ]] && [[ $OK_freetype -eq 1 ]]; then
        run=1
      fi
      ;;
    freetype)
      if [[ $OK_libpng -eq 1 ]]; then
        run=1
      fi
      ;;
    gnutls)
      if [[ $OK_nettle -eq 1 ]] && [[ $OK_gmp -eq 1 ]] && [[ $OK_libiconv -eq 1 ]]; then
        run=1
      fi
      ;;
    harfbuzz)
      if [[ $OK_fontconfig -eq 1 ]] && [[ $OK_freetype -eq 1 ]]; then
        run=1
      fi
      ;;
    lame)
      if [[ $OK_libiconv -eq 1 ]]; then
        run=1
      fi
      ;;
    leptonica)
      if [[ $OK_giflib -eq 1 ]] && [[ $OK_jpeg -eq 1 ]] && [[ $OK_libpng -eq 1 ]] && [[ $OK_tiff -eq 1 ]] && [[ $OK_libwebp -eq 1 ]]; then
        run=1
      fi
      ;;
    libass)
      if [[ $OK_libuuid -eq 1 ]] && [[ $OK_expat -eq 1 ]] && [[ $OK_libiconv -eq 1 ]] && [[ $OK_freetype -eq 1 ]] && [[ $OK_fribidi -eq 1 ]] && [[ $OK_fontconfig -eq 1 ]] && [[ $OK_libpng -eq 1 ]] && [[ $OK_harfbuzz -eq 1 ]]; then
        run=1
      fi
      ;;
    libtheora)
      if [[ $OK_libvorbis -eq 1 ]] && [[ $OK_libogg -eq 1 ]]; then
        run=1
      fi
      ;;
    libvorbis)
      if [[ $OK_libogg -eq 1 ]]; then
        run=1
      fi
      ;;
    libvpx)
      if [[ $OK_cpu_features -eq 1 ]]; then
        run=1
      fi
      ;;
    libwebp)
      if [[ $OK_giflib -eq 1 ]] && [[ $OK_jpeg -eq 1 ]] && [[ $OK_libpng -eq 1 ]] && [[ $OK_tiff -eq 1 ]]; then
        run=1
      fi
      ;;
    libxml2)
      if [[ $OK_libiconv -eq 1 ]]; then
        run=1
      fi
      ;;
    nettle)
      if [[ $OK_gmp -eq 1 ]]; then
        run=1
      fi
      ;;
    openh264)
      if [[ $OK_cpu_features -eq 1 ]]; then
        run=1
      fi
      ;;
    rubberband)
      if [[ $OK_libsndfile -eq 1 ]] && [[ $OK_libsamplerate -eq 1 ]]; then
        run=1
      fi
      ;;
    srt)
      if [[ $OK_openssl -eq 1 ]]; then
        run=1
      fi
      ;;
    tesseract)
      if [[ $OK_leptonica -eq 1 ]]; then
        run=1
      fi
      ;;
    tiff)
      if [[ $OK_jpeg -eq 1 ]]; then
        run=1
      fi
      ;;
    twolame)
      if [[ $OK_libsndfile -eq 1 ]]; then
        run=1
      fi
      ;;
    *)
      run=1
      ;;
    esac

    # DEFINE SOME FLAGS TO MANAGE DEPENDENCIES AND REBUILD OPTIONS
    BUILD_COMPLETED_FLAG=$(echo "OK_${library}" | sed "s/\-/\_/g")
    REBUILD_FLAG=$(echo "REBUILD_${library}" | sed "s/\-/\_/g")
    DEPENDENCY_REBUILT_FLAG=$(echo "DEPENDENCY_REBUILT_${library}" | sed "s/\-/\_/g")

    if [[ $run -eq 1 ]] && [[ "${!BUILD_COMPLETED_FLAG}" != "1" ]]; then
      LIBRARY_IS_INSTALLED=$(library_is_installed "${LIB_INSTALL_BASE}" "${library}")

      echo -e "INFO: Flags detected for ${library}: already installed=${LIBRARY_IS_INSTALLED}, rebuild requested by user=${!REBUILD_FLAG}, will be rebuilt due to dependency update=${!DEPENDENCY_REBUILT_FLAG}\n" 1>>"${BASEDIR}"/build.log 2>&1

      # CHECK IF BUILD IS NECESSARY OR NOT
      if [[ ${LIBRARY_IS_INSTALLED} -ne 1 ]] || [[ ${!REBUILD_FLAG} -eq 1 ]] || [[ ${!DEPENDENCY_REBUILT_FLAG} -eq 1 ]]; then

        echo -n "${library}: "

        "${BASEDIR}"/scripts/run-android.sh "${library}" 1>>"${BASEDIR}"/build.log 2>&1

        RC=$?

        # SET SOME FLAGS AFTER THE BUILD
        if [ $RC -eq 0 ]; then
          ((completed += 1))
          declare "$BUILD_COMPLETED_FLAG=1"
          check_if_dependency_rebuilt "${library}"
          echo "ok"
        elif [ $RC -eq 200 ]; then
          echo -e "not supported\n\nSee build.log for details\n"
          exit 1
        else
          echo -e "failed\n\nSee build.log for details\n"
          exit 1
        fi
      else
        ((completed += 1))
        declare "$BUILD_COMPLETED_FLAG=1"
        echo "${library}: already built"
      fi
    else
      echo -e "INFO: Skipping $library, dependencies built=$run, already built=${!BUILD_COMPLETED_FLAG}\n" 1>>"${BASEDIR}"/build.log 2>&1
      # If library is already built, increment completed to avoid infinite loop
      if [[ "${!BUILD_COMPLETED_FLAG}" == "1" ]]; then
        ((completed += 1))
      # If dependencies are not met (run=0), check if dependencies are enabled
      # If dependencies are disabled, mark library as completed (it can never be built)
      elif [[ $run -eq 0 ]]; then
        deps_missing=0
        case $library in
        fontconfig)
          if ! is_library_enabled "libuuid" || ! is_library_enabled "expat" || ! is_library_enabled "libiconv" || ! is_library_enabled "freetype"; then
            deps_missing=1
          fi
          ;;
        freetype)
          if ! is_library_enabled "libpng"; then
            deps_missing=1
          fi
          ;;
        gnutls)
          if ! is_library_enabled "nettle" || ! is_library_enabled "gmp" || ! is_library_enabled "libiconv"; then
            deps_missing=1
          fi
          ;;
        harfbuzz)
          if ! is_library_enabled "fontconfig" || ! is_library_enabled "freetype"; then
            deps_missing=1
          fi
          ;;
        lame)
          if ! is_library_enabled "libiconv"; then
            deps_missing=1
          fi
          ;;
        leptonica)
          if ! is_library_enabled "giflib" || ! is_library_enabled "jpeg" || ! is_library_enabled "libpng" || ! is_library_enabled "tiff" || ! is_library_enabled "libwebp"; then
            deps_missing=1
          fi
          ;;
        libass)
          if ! is_library_enabled "libuuid" || ! is_library_enabled "expat" || ! is_library_enabled "libiconv" || ! is_library_enabled "freetype" || ! is_library_enabled "fribidi" || ! is_library_enabled "fontconfig" || ! is_library_enabled "libpng" || ! is_library_enabled "harfbuzz"; then
            deps_missing=1
          fi
          ;;
        libtheora)
          if ! is_library_enabled "libvorbis" || ! is_library_enabled "libogg"; then
            deps_missing=1
          fi
          ;;
        libvorbis)
          if ! is_library_enabled "libogg"; then
            deps_missing=1
          fi
          ;;
        libvpx)
          if ! is_library_enabled "cpu-features"; then
            deps_missing=1
          fi
          ;;
        libwebp)
          if ! is_library_enabled "giflib" || ! is_library_enabled "jpeg" || ! is_library_enabled "libpng" || ! is_library_enabled "tiff"; then
            deps_missing=1
          fi
          ;;
        libxml2)
          if ! is_library_enabled "libiconv"; then
            deps_missing=1
          fi
          ;;
        nettle)
          if ! is_library_enabled "gmp"; then
            deps_missing=1
          fi
          ;;
        openh264)
          if ! is_library_enabled "cpu-features"; then
            deps_missing=1
          fi
          ;;
        rubberband)
          if ! is_library_enabled "libsndfile" || ! is_library_enabled "libsamplerate"; then
            deps_missing=1
          fi
          ;;
        srt)
          if ! is_library_enabled "openssl"; then
            deps_missing=1
          fi
          ;;
        tesseract)
          if ! is_library_enabled "leptonica"; then
            deps_missing=1
          fi
          ;;
        tiff)
          if ! is_library_enabled "jpeg"; then
            deps_missing=1
          fi
          ;;
        twolame)
          if ! is_library_enabled "libsndfile"; then
            deps_missing=1
          fi
          ;;
        esac
        # If dependencies are disabled, check if library is already installed
        # Only mark as completed if it's actually installed
        # If not installed, we'll skip it but not mark as completed to avoid breaking dependent libraries
        if [[ $deps_missing -eq 1 ]]; then
          LIBRARY_IS_INSTALLED=$(library_is_installed "${LIB_INSTALL_BASE}" "${library}")
          if [[ ${LIBRARY_IS_INSTALLED} -eq 1 ]]; then
            # Library is already installed, mark as completed
            ((completed += 1))
            declare "$BUILD_COMPLETED_FLAG=1"
            echo -e "INFO: Marking $library as completed (already installed, dependencies are disabled)\n" 1>>"${BASEDIR}"/build.log 2>&1
          else
            # Library is not installed and can't be built due to missing dependencies
            # Don't mark as completed - this prevents dependent libraries from thinking the dependency is available
            # The progress tracking below will handle infinite loop prevention
            echo -e "INFO: Skipping $library (dependencies disabled, not installed, cannot be built)\n" 1>>"${BASEDIR}"/build.log 2>&1
          fi
        fi
      fi
    fi
  done
  # Check if we made progress in this iteration
  if [[ $completed -eq $previous_completed ]]; then
    ((no_progress_iterations++))
    # If we've had multiple iterations with no progress, we need to break the loop
    # Mark unbuildable libraries as completed (but don't set OK_* flag to avoid breaking dependencies)
    if [[ $no_progress_iterations -gt ${#enabled_library_list[@]} ]]; then
      echo -e "INFO: No progress detected after $no_progress_iterations iterations, marking unbuildable libraries\n" 1>>"${BASEDIR}"/build.log 2>&1
      for library in "${enabled_library_list[@]}"; do
        BUILD_COMPLETED_FLAG=$(echo "OK_${library}" | sed "s/\-/\_/g")
        if [[ "${!BUILD_COMPLETED_FLAG}" != "1" ]]; then
          LIBRARY_IS_INSTALLED=$(library_is_installed "${LIB_INSTALL_BASE}" "${library}")
          if [[ ${LIBRARY_IS_INSTALLED} -ne 1 ]]; then
            # Use a separate tracking variable instead of OK_* to avoid breaking dependencies
            TRACK_COMPLETED_FLAG=$(echo "TRACK_${library}" | sed "s/\-/\_/g")
            if [[ "${!TRACK_COMPLETED_FLAG}" != "1" ]]; then
              declare "$TRACK_COMPLETED_FLAG=1"
              ((completed += 1))
              echo -e "INFO: Marking $library as tracked (cannot be built, no progress)\n" 1>>"${BASEDIR}"/build.log 2>&1
            fi
          fi
        fi
      done
    fi
  else
    no_progress_iterations=0
  fi
  previous_completed=$completed
done

# BUILD CUSTOM LIBRARIES
for custom_library_index in "${CUSTOM_LIBRARIES[@]}"; do
  library_name="CUSTOM_LIBRARY_${custom_library_index}_NAME"

  echo -e "\nDEBUG: Custom library ${!library_name} will be built\n" 1>>"${BASEDIR}"/build.log 2>&1

  # DEFINE SOME FLAGS TO REBUILD OPTIONS
  REBUILD_FLAG=$(echo "REBUILD_${!library_name}" | sed "s/\-/\_/g")
  LIBRARY_IS_INSTALLED=$(library_is_installed "${LIB_INSTALL_BASE}" "${!library_name}")

  echo -e "INFO: Flags detected for custom library ${!library_name}: already installed=${LIBRARY_IS_INSTALLED}, rebuild requested by user=${!REBUILD_FLAG}\n" 1>>"${BASEDIR}"/build.log 2>&1

  if [[ ${LIBRARY_IS_INSTALLED} -ne 1 ]] || [[ ${!REBUILD_FLAG} -eq 1 ]]; then

    echo -n "${!library_name}: "

    "${BASEDIR}"/scripts/run-android.sh "${!library_name}" 1>>"${BASEDIR}"/build.log 2>&1

    RC=$?

    # SET SOME FLAGS AFTER THE BUILD
    if [ $RC -eq 0 ]; then
      echo "ok"
    elif [ $RC -eq 200 ]; then
      echo -e "not supported\n\nSee build.log for details\n"
      exit 1
    else
      echo -e "failed\n\nSee build.log for details\n"
      exit 1
    fi
  else
    echo "${!library_name}: already built"
  fi
done

# SKIP TO SPEED UP THE BUILD
if [[ ${SKIP_ffmpeg} -ne 1 ]]; then

  # BUILD FFMPEG
  source "${BASEDIR}"/scripts/android/ffmpeg.sh

  if [[ $? -ne 0 ]]; then
    exit 1
  fi
else
  echo -e "\nffmpeg: skipped"
fi

echo -e "\nINFO: Completed build for ${ARCH} on API level ${API} at $(date)\n" 1>>"${BASEDIR}"/build.log 2>&1
