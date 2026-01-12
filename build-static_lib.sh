#!/usr/bin/env bash

set -e

CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:=Release}
SOURCE_DIR=${SOURCE_DIR:=static_lib}
BUILD_DIR=${BUILD_DIR:=build/static_lib}
OUTPUT_DIR=${OUTPUT_DIR:=output/static_lib}
ONNXRUNTIME_SOURCE_DIR=${ONNXRUNTIME_SOURCE_DIR:=onnxruntime}
ONNXRUNTIME_VERSION=${ONNXRUNTIME_VERSION:=$(cat ONNXRUNTIME_VERSION)}
CMAKE_OPTIONS=$CMAKE_OPTIONS
CMAKE_BUILD_OPTIONS=$CMAKE_BUILD_OPTIONS

echo "CMAKE_BUILD_TYPE: $CMAKE_BUILD_TYPE"
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
    --compile-no-warning-as-error \
    $CMAKE_OPTIONS
cmake \
    --build $BUILD_DIR \
    --config $CMAKE_BUILD_TYPE \
    --parallel $PARALLEL_JOB_COUNT \
    $CMAKE_BUILD_OPTIONS
cmake --install $BUILD_DIR --config $CMAKE_BUILD_TYPE

# cmake \
#     -S $SOURCE_DIR/tests \
#     -B $BUILD_DIR/tests \
#     -D ONNXRUNTIME_SOURCE_DIR=$(pwd)/$ONNXRUNTIME_SOURCE_DIR \
#     -D ONNXRUNTIME_LIB_DIR=$(pwd)/$OUTPUT_DIR/lib
# cmake --build $BUILD_DIR/tests
# ctest --test-dir $BUILD_DIR/tests --build-config Debug --verbose --no-tests=error
