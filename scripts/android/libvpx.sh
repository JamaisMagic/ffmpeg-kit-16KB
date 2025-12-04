#!/bin/bash

# UPDATE BUILD FLAGS
export CFLAGS="$(get_cflags "${LIB_NAME}") -I${LIB_INSTALL_BASE}/cpu-features/include/ndk_compat"
export LDFLAGS="$(get_ldflags "${LIB_NAME}")"

# For libvpx configure with NDK r27, we need to ensure the linker can find system libraries
# The configure script uses ${LD} (lld) directly, so we need to add sysroot to LDFLAGS
# Also, pass linker flags via CFLAGS/CXXFLAGS so the compiler passes them through
export LDFLAGS="${LDFLAGS} --sysroot=${ANDROID_SYSROOT}"

# Remove the host library path from LDFLAGS to prevent linking against x86_64 libraries
# The host library path (-L${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${TOOLCHAIN}/lib) 
# contains x86_64 libraries that are incompatible with ARM targets
# We need to remove this specific path pattern from LDFLAGS
# Match only the path ending with /toolchains/llvm/prebuilt/TOOLCHAIN/lib (without subdirectories)
# This is the host library path, not the ARM-specific paths like .../arm-linux-androideabi/lib or .../sysroot/...
export LDFLAGS=$(echo "${LDFLAGS}" | sed -E "s|-L[^ ]*/toolchains/llvm/prebuilt/[^ /]+/lib([[:space:]]|$)||g")

# Extract linker flags (those starting with -Wl,) and add them to CFLAGS/CXXFLAGS
# This ensures the configure script's test linking works when using the compiler
LINKER_FLAGS_ONLY=$(echo "${LDFLAGS}" | grep -oE '\-Wl,[^ ]+' | tr '\n' ' ')
export CFLAGS="${CFLAGS} ${LINKER_FLAGS_ONLY}"
export CXXFLAGS="${CXXFLAGS} ${LINKER_FLAGS_ONLY}"

# Set LD to CC for libvpx configure to ensure proper linking with sysroot
# This is crucial for NDK r27+ where standalone lld might not pick up sysroot correctly
export LD="${CC}"

# SET BUILD OPTIONS
TARGET_CPU=""
ASM_OPTIONS=""
case ${ARCH} in
arm-v7a)
  TARGET_CPU="armv7"

  # NEON disabled explicitly because
  # --enable-runtime-cpu-detect enables NEON for armv7 cpu
  ASM_OPTIONS="--disable-neon"
  export ASFLAGS="-c"
  ;;
arm-v7a-neon)
  # NEON IS ENABLED BY --enable-runtime-cpu-detect
  TARGET_CPU="armv7"
  export ASFLAGS="-c"
  ;;
arm64-v8a)
  # NEON IS ENABLED BY --enable-runtime-cpu-detect
  TARGET_CPU="arm64"
  export ASFLAGS="-c"
  ;;
*)
  # INTEL CPU EXTENSIONS ENABLED BY --enable-runtime-cpu-detect
  TARGET_CPU="$(get_target_cpu)"
  export ASFLAGS="-D__ANDROID__"
  ;;
esac

# ALWAYS CLEAN THE PREVIOUS BUILD
make distclean 2>/dev/null 1>/dev/null

# NOTE THAT RECONFIGURE IS NOT SUPPORTED

# WORKAROUND TO FIX BUILD OPTIONS DEFINED IN configure.sh
overwrite_file "${BASEDIR}"/tools/patch/make/libvpx/configure.sh "${BASEDIR}"/src/"${LIB_NAME}"/build/make/configure.sh || return 1

./configure \
  --prefix="${LIB_INSTALL_PREFIX}" \
  --target="${TARGET_CPU}-android-gcc" \
  --extra-cflags="${CFLAGS}" \
  --extra-cxxflags="${CXXFLAGS}" \
  --as=yasm \
  --log=yes \
  --enable-libs \
  --enable-install-libs \
  --enable-pic \
  --enable-optimizations \
  --enable-better-hw-compatibility \
  --enable-runtime-cpu-detect \
  --enable-vp9-highbitdepth \
  ${ASM_OPTIONS} \
  --enable-vp8 \
  --enable-vp9 \
  --enable-multithread \
  --enable-spatial-resampling \
  --enable-small \
  --enable-static \
  --disable-realtime-only \
  --disable-shared \
  --disable-debug \
  --disable-gprof \
  --disable-gcov \
  --disable-ccache \
  --disable-install-bins \
  --disable-install-srcs \
  --disable-install-docs \
  --disable-docs \
  --disable-tools \
  --disable-examples \
  --disable-unit-tests \
  --disable-decode-perf-tests \
  --disable-encode-perf-tests \
  --disable-codec-srcs \
  --disable-debug-libs \
  --disable-internal-stats || return 1

make -j$(get_cpu_count) || return 1

make install || return 1

# MANUALLY COPY PKG-CONFIG FILES
cp ./*.pc "${INSTALL_PKG_CONFIG_DIR}" || return 1
