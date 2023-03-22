#!/usr/bin/env bash

set -e

LIB_NAME=${LIB_NAME:=onnxruntime_webassembly}
BUILD_DIR=build/wasm-static-lib
OUTPUT_DIR=${OUTPUT_DIR:=outputs/wasm-static-lib}
ONNXRUNTIME_SOURCE_DIR=onnxruntime
EMSDK_DIR=$ONNXRUNTIME_SOURCE_DIR/cmake/external/emsdk
BUILD_OPTIONS="\
    --build_dir $BUILD_DIR \
    --config Release \
    --build_wasm_static_lib \
    --skip_tests \
    --disable_wasm_exception_catching \
    --disable_rtti \
    --parallel \
    $BUILD_OPTIONS \
"
SKIP_TESTS=${SKIP_TESTS:=false}

git submodule update --init --recursive

$EMSDK_DIR/emsdk install latest
$EMSDK_DIR/emsdk activate latest
source $EMSDK_DIR/emsdk_env.sh

rm -f $BUILD_DIR/Release/libonnxruntime_webassembly.a

$ONNXRUNTIME_SOURCE_DIR/build.sh $BUILD_OPTIONS

mkdir -p $OUTPUT_DIR/include
cp $ONNXRUNTIME_SOURCE_DIR/include/onnxruntime/core/session/onnxruntime_c_api.h $OUTPUT_DIR/include
cp $ONNXRUNTIME_SOURCE_DIR/include/onnxruntime/core/session/onnxruntime_cxx_api.h $OUTPUT_DIR/include
cp $ONNXRUNTIME_SOURCE_DIR/include/onnxruntime/core/session/onnxruntime_cxx_inline.h $OUTPUT_DIR/include

mkdir -p $OUTPUT_DIR/lib
cp $BUILD_DIR/Release/libonnxruntime_webassembly.a $OUTPUT_DIR/lib/lib$LIB_NAME.a
ln -sf lib$LIB_NAME.a $OUTPUT_DIR/lib/libonnxruntime.a

if [ $SKIP_TESTS = true ]; then
    exit 0
fi

cmake \
    -S wasm-static-lib/tests \
    -B $BUILD_DIR/tests \
    -D ONNXRUNTIME_SOURCE_DIR=onnxruntime \
    -D ONNXRUNTIME_LIB_DIR=$OUTPUT_DIR/lib \
    -D CMAKE_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake
cmake --build $BUILD_DIR/tests --clean-first
ctest --test-dir $BUILD_DIR/tests --verbose --no-tests=error
