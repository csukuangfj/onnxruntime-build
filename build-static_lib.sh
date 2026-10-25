#!/usr/bin/env bash

set -e

CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:=Release}
SOURCE_DIR=${SOURCE_DIR:=static_lib}
BUILD_DIR=${BUILD_DIR:=build/static_lib}
OUTPUT_DIR=${OUTPUT_DIR:=output/static_lib}
ONNXRUNTIME_SOURCE_DIR=${ONNXRUNTIME_SOURCE_DIR:=onnxruntime}
ONNXRUNTIME_VERSION=${ONNXRUNTIME_VERSION:=$(cat ONNXRUNTIME_VERSION)}
# 1 = C++11 libstdc++ ABI (stock gcc's default); 0 = old gcc4-compatible COW ABI
# (Red Hat SCL devtoolset's default); empty = do not touch the macro at all and
# take the toolchain default. Linux only. See static_lib/CMakeLists.txt.
CXX11_ABI=${CXX11_ABI:-}
CMAKE_OPTIONS=$CMAKE_OPTIONS
CMAKE_BUILD_OPTIONS=$CMAKE_BUILD_OPTIONS

echo "CMAKE_BUILD_TYPE: $CMAKE_BUILD_TYPE"
echo "CXX11_ABI: ${CXX11_ABI:-(toolchain default)}"
echo "CMAKE_BUILD_OPTIONS: $CMAKE_BUILD_OPTIONS"

case $(uname -s) in
Darwin) CPU_COUNT=$(sysctl -n hw.physicalcpu) ;;
Linux) CPU_COUNT=$(grep ^cpu\\scores /proc/cpuinfo | uniq | awk '{print $4}') ;;
*) CPU_COUNT=$NUMBER_OF_PROCESSORS ;;
esac
PARALLEL_JOB_COUNT=${PARALLEL_JOB_COUNT:=$CPU_COUNT}

cd $(dirname $0)
echo "pwd: $PWD"

(
    git submodule update --init --depth=1 $ONNXRUNTIME_SOURCE_DIR
    cd $ONNXRUNTIME_SOURCE_DIR
    if [ $ONNXRUNTIME_VERSION != $(cat VERSION_NUMBER) ]; then
        git fetch origin tag v$ONNXRUNTIME_VERSION
        git checkout v$ONNXRUNTIME_VERSION
    fi
    git submodule update --init --depth=1 --recursive
    echo "inside pwd: $PWD"
    echo "---"
    ls -lh
    echo "---"

    sed -i.bak '/SOVERSION/d' ./cmake/onnxruntime.cmake

    # Fix: sqnbitgemm_kernel_avx512_2bit.cpp is a portable scalar helper
    # (no x86 intrinsics) that is shared between the ARM64 and x86_64
    # targets in a universal2 build.  The x86_64 section sets
    # set_source_files_properties() with x86 flags (-mfma -mavx512bw ...)
    # which are global (not per-target) and leak into the arm64 target,
    # causing: "unsupported option '-mfma' for target 'arm64-apple-darwin'".
    # Clear those flags so the arm64 build sees no x86 options.
    if [[ "$CMAKE_OPTIONS" =~ "-DCMAKE_OSX_ARCHITECTURES" ]]; then
      MLAS_CMAKE="cmake/onnxruntime_mlas.cmake"
      # Replace the x86 flags on sqnbitgemm_kernel_avx512_2bit.cpp with empty
      # flags.  The file is pure C++ with no intrinsics so empty flags are safe.
      python3 -c "
import re, sys
with open('cmake/onnxruntime_mlas.cmake') as f:
    content = f.read()
# Match the set_source_files_properties for this file (spans two lines)
content = re.sub(
    r'(set_source_files_properties\(.+?sqnbitgemm_kernel_avx512_2bit\.cpp\s+PROPERTIES\s+)COMPILE_FLAGS\s+\"[^\"]*\"',
    r'\1COMPILE_FLAGS \"\"',
    content,
    flags=re.DOTALL
)
with open('cmake/onnxruntime_mlas.cmake', 'w') as f:
    f.write(content)
"
      echo "✅ Patched $MLAS_CMAKE to clear x86 flags on sqnbitgemm_kernel_avx512_2bit.cpp for arm64."
    fi

      # The following if has been moved to CMakeLists.txt
      # See also
      # https://github.com/supertone-inc/onnxruntime-build/commit/0ed115ff1d26c3d1b5cb641634c277d190442c1e
#     if [[ "$CMAKE_OPTIONS" =~ "-DCMAKE_OSX_ARCHITECTURES" ]]; then
#       MLAS_CMAKE_FILE="cmake/onnxruntime_mlas.cmake"
#
#       cat <<'EOF' >> "$MLAS_CMAKE_FILE"
# # --- PATCH: Export multi-arch MLAS targets for static builds ---
# if(ONNXRUNTIME_MLAS_MULTI_ARCH AND NOT onnxruntime_BUILD_SHARED_LIB)
#     if(TARGET onnxruntime_mlas_arm64)
#         install(TARGETS onnxruntime_mlas_arm64
#                 EXPORT ${PROJECT_NAME}Targets
#                 ARCHIVE   DESTINATION ${CMAKE_INSTALL_LIBDIR}
#                 LIBRARY   DESTINATION ${CMAKE_INSTALL_LIBDIR}
#                 RUNTIME   DESTINATION ${CMAKE_INSTALL_BINDIR})
#     endif()
#     if(TARGET onnxruntime_mlas_x86_64)
#         install(TARGETS onnxruntime_mlas_x86_64
#                 EXPORT ${PROJECT_NAME}Targets
#                 ARCHIVE   DESTINATION ${CMAKE_INSTALL_LIBDIR}
#                 LIBRARY   DESTINATION ${CMAKE_INSTALL_LIBDIR}
#                 RUNTIME   DESTINATION ${CMAKE_INSTALL_BINDIR})
#     endif()
# endif()
# # --- END PATCH ---
# EOF
#
#       echo "✅ Patched $MLAS_CMAKE_FILE to export multi-arch MLAS targets."
#     fi
    git diff .
)

echo "pwd: $PWD"
ls -lh



cmake \
    -S $SOURCE_DIR \
    -B $BUILD_DIR \
    -D CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE \
    -D CMAKE_CONFIGURATION_TYPES=$CMAKE_BUILD_TYPE \
    -D CMAKE_INSTALL_PREFIX=$OUTPUT_DIR \
    -D ONNXRUNTIME_SOURCE_DIR=$(pwd)/$ONNXRUNTIME_SOURCE_DIR \
    -D CXX11_ABI=$CXX11_ABI \
    --compile-no-warning-as-error \
    $CMAKE_OPTIONS
cmake \
    --build $BUILD_DIR \
    --config $CMAKE_BUILD_TYPE \
    --parallel $PARALLEL_JOB_COUNT \
    $CMAKE_BUILD_OPTIONS
cmake --install $BUILD_DIR --config $CMAKE_BUILD_TYPE

# cmake puts the archives in lib64 on RedHat-based images and in lib on
# Debian-based ones (manylinux_2_24 has no lib64 at all). Normalise to lib so
# consumers -- and the test harness below -- always find them in one place.
if [ -d "$OUTPUT_DIR/lib64" ]; then
    mkdir -p "$OUTPUT_DIR/lib"
    mv "$OUTPUT_DIR"/lib64/* "$OUTPUT_DIR/lib/"
    rmdir "$OUTPUT_DIR/lib64"
    echo "Normalised $OUTPUT_DIR/lib64 -> $OUTPUT_DIR/lib"
fi

# Verify the archive really was built with the requested _GLIBCXX_USE_CXX11_ABI.
# The two ABIs mangle std::string differently: the C++11 ABI references
# std::__cxx11::basic_string, the old gcc4-compatible one references the COW
# std::basic_string (mangled with 'Ss'). Shipping the wrong variant makes
# consumers abort at startup with "free(): invalid pointer".
# Only meaningful where the target uses GNU libstdc++. Android (libc++,
# std::__ndk1) and wasm have no _GLIBCXX_USE_CXX11_ABI at all, and CMake
# records those targets as "none". Note the *host* is irrelevant: Android
# and wasm builds run on a Linux runner too.
abi_expected=none
if [ -f "$BUILD_DIR/cxx11-abi.txt" ]; then
    abi_expected=$(tr -d '[:space:]' < "$BUILD_DIR/cxx11-abi.txt")
fi
if [ "$abi_expected" = "0" ] || [ "$abi_expected" = "1" ]; then
    lib=$(find "$OUTPUT_DIR" -name 'libonnxruntime.a' | head -1)
    if [ -z "$lib" ]; then
        echo "ERROR: libonnxruntime.a not found under $OUTPUT_DIR" >&2
        exit 1
    fi
    undef=$(nm --undefined-only "$lib" | awk '{print $NF}' | sort -u)
    new_abi=$(printf '%s\n' "$undef" | grep -c '__cxx11' || true)
    old_abi=$(printf '%s\n' "$undef" | grep -cE '^_ZNSs|^_ZNSb' || true)
    echo "ABI check for $lib"
    echo "  requested _GLIBCXX_USE_CXX11_ABI: $abi_expected"
    echo "  std::__cxx11 references (new ABI): $new_abi"
    echo "  old COW std::string references:   $old_abi"
    if [ "$abi_expected" = "1" ] && [ "$new_abi" -eq 0 ]; then
        echo "ERROR: CXX11_ABI=1 but the archive has no std::__cxx11 references." >&2
        echo "       The toolchain overrode the ABI (Red Hat SCL devtoolset defaults" >&2
        echo "       to _GLIBCXX_USE_CXX11_ABI=0). Do not ship this artifact." >&2
        exit 1
    fi
    if [ "$abi_expected" = "0" ] && [ "$old_abi" -eq 0 ]; then
        echo "ERROR: CXX11_ABI=0 but the archive has no old-COW std::string references." >&2
        exit 1
    fi
else
    echo "Skipping _GLIBCXX_USE_CXX11_ABI check (target is not GNU libstdc++: $abi_expected)"
fi

SKIP_TEST=${SKIP_TEST:-0}
if [ "$SKIP_TEST" -eq 0 ]; then
    # Extract -A <platform> from CMAKE_OPTIONS if present (e.g., Win32, x64, ARM64)
    TEST_PLATFORM_FLAG=""
    if [[ "$CMAKE_OPTIONS" =~ -A[[:space:]]+([A-Za-z0-9_]+) ]]; then
        TEST_PLATFORM_FLAG="-A ${BASH_REMATCH[1]}"
    fi
    cmake \
        -S $SOURCE_DIR/tests \
        -B $BUILD_DIR/tests \
        -D ONNXRUNTIME_INCLUDE_DIR=$(pwd)/$OUTPUT_DIR/include \
        -D ONNXRUNTIME_LIB_DIR=$(pwd)/$OUTPUT_DIR/lib \
        $TEST_PLATFORM_FLAG
    cmake --build $BUILD_DIR/tests --config $CMAKE_BUILD_TYPE
    ctest --test-dir $BUILD_DIR/tests --build-config $CMAKE_BUILD_TYPE --verbose --no-tests=error
else
    echo "Skipping test (SKIP_TEST=1)"
fi
