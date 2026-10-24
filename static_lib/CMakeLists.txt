if (CMAKE_VERSION VERSION_GREATER_EQUAL "4.0.0")
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
endif()
cmake_minimum_required(VERSION 3.28)

# https://cmake.org/cmake/help/latest/prop_tgt/MSVC_RUNTIME_LIBRARY.html
cmake_policy(SET CMP0091 NEW)

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum OS X deployment version. Used only for macOS")
project(onnxruntime_static_lib)

# see
# https://www.amd.com/en/developer/resources/technical-articles/2026/a-practical-approach-to-using-sherpa-onnx-production-ready-on-wi.html
# and
# https://github.com/wolfball/PlenVDB/tree/7e4933191f94a224c7f620457d0acd53111c6111/openvdb/doc
# For more information, see the following articles:
# Description of CRT selection: https://docs.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library
# In depth descriptopn of the CRT on Windows: https://docs.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features
# Related errors: https://docs.microsoft.com/en-us/cpp/error-messages/tool-errors/linker-tools-error-lnk2038
# `CMAKE_MSVC_RUNTIME_LIBRARY` docs: https://cmake.org/cmake/help/latest/variable/CMAKE_MSVC_RUNTIME_LIBRARY.html


option(USE_STATIC_CRT "ON to use static CRT (/MT /MTd); OFF to use dynamic (/MD /MDd)" ON)

if(MSVC)
    if(CMAKE_BUILD_TYPE MATCHES Debug)
        if(USE_STATIC_CRT)
            set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDebug" CACHE STRING "CRT type" FORCE)
        else()
            set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDebugDLL" CACHE STRING "CRT type" FORCE)
        endif()
    else()
        # Release / RelWithDebInfo / MinSizeRel
        if(USE_STATIC_CRT)
            set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded" CACHE STRING "CRT type" FORCE)
        else()
            set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "CRT type" FORCE)
        endif()
    endif()

    set(ONNX_USE_MSVC_STATIC_RUNTIME ${USE_STATIC_CRT} CACHE BOOL "" FORCE)
    set(protobuf_MSVC_STATIC_RUNTIME ${USE_STATIC_CRT} CACHE BOOL "" FORCE)
    set(ABSL_MSVC_STATIC_RUNTIME ${USE_STATIC_CRT} CACHE BOOL "" FORCE)
endif()

message(STATUS "USE_STATIC_CRT: ${USE_STATIC_CRT}")
message(STATUS "CMAKE_MSVC_RUNTIME_LIBRARY: ${CMAKE_MSVC_RUNTIME_LIBRARY}")

set(onnxruntime_BUILD_SHARED_LIB OFF)

# Which libstdc++ ABI to build with.
#
#   1 = the C++11 ABI (std::__cxx11::basic_string). This is the default for
#       every stock gcc >= 5.
#   0 = the old gcc4-compatible COW ABI.
#
# Red Hat SCL devtoolset is configured --with-default-libstdcxx-abi=gcc4-compatible,
# so it defaults to 0, while stock gcc defaults to 1. Mixing the two in a single
# process corrupts the heap at startup ("free(): invalid pointer"): onnxruntime
# creates std::filesystem::path objects with one layout while the non-inline
# members of path (_M_split_cmpts, operator=) come from a libstdc++ built with
# the other. So we build and publish both variants; see the release job names
# for the -cxx11-abi artifact.
set(CXX11_ABI "1" CACHE STRING "Value for _GLIBCXX_USE_CXX11_ABI (0 or 1). GNU libstdc++ only.")
set_property(CACHE CXX11_ABI PROPERTY STRINGS 0 1)

# _GLIBCXX_USE_CXX11_ABI is a GNU libstdc++ concept. It does not exist for
# LLVM libc++ (Android NDK r18+, which uses std::__ndk1 and has a single fixed
# string ABI) nor for Emscripten. Setting it there is a no-op at best, so we
# only apply it when the target is Linux/libstdc++.
#
# Record the decision so build-static_lib.sh can verify the produced archive
# against the ABI that was actually requested.
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  if(NOT CXX11_ABI MATCHES "^[01]$")
    message(FATAL_ERROR "CXX11_ABI must be 0 or 1, got: '${CXX11_ABI}'")
  endif()
  string(APPEND CMAKE_CXX_FLAGS " -D_GLIBCXX_USE_CXX11_ABI=${CXX11_ABI}")
  message(STATUS "_GLIBCXX_USE_CXX11_ABI: ${CXX11_ABI}")
  set(_cxx11_abi_used "${CXX11_ABI}")
else()
  # Targets that don't use GNU libstdc++ have no dual ABI: Android NDK's libc++
  # (std::__ndk1, a single fixed string ABI), Emscripten, MSVC and Apple's libc++.
  # There is nothing to choose and nothing to verify, so always use 0 and never
  # produce a cxx11-abi variant here.
  if(NOT CXX11_ABI STREQUAL "0")
    message(STATUS "CXX11_ABI=${CXX11_ABI} ignored: target ${CMAKE_SYSTEM_NAME} has no _GLIBCXX_USE_CXX11_ABI (pinning to 0)")
  endif()
  set(CXX11_ABI "0")
  message(STATUS "_GLIBCXX_USE_CXX11_ABI: 0 (not applicable for target system ${CMAKE_SYSTEM_NAME})")
  set(_cxx11_abi_used "none")
endif()
file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/cxx11-abi.txt "${_cxx11_abi_used}\n")

add_definitions(-D_SILENCE_ALL_CXX23_DEPRECATION_WARNINGS)

add_subdirectory(${ONNXRUNTIME_SOURCE_DIR}/cmake onnxruntime EXCLUDE_FROM_ALL)

# Fix export set for architecture-specific MLAS libraries
if(APPLE AND CMAKE_OSX_ARCHITECTURES)
    list(LENGTH CMAKE_OSX_ARCHITECTURES ARCH_COUNT)
    if(ARCH_COUNT GREATER 1)
        # Add architecture-specific MLAS libraries to export set
        if("arm64" IN_LIST CMAKE_OSX_ARCHITECTURES AND TARGET onnxruntime_mlas_arm64)
            install(TARGETS onnxruntime_mlas_arm64 EXPORT onnxruntimeTargets
                    ARCHIVE   DESTINATION lib
                    LIBRARY   DESTINATION lib
                    RUNTIME   DESTINATION bin
                    FRAMEWORK DESTINATION bin)
        endif()
        if("x86_64" IN_LIST CMAKE_OSX_ARCHITECTURES AND TARGET onnxruntime_mlas_x86_64)
            install(TARGETS onnxruntime_mlas_x86_64 EXPORT onnxruntimeTargets
                    ARCHIVE   DESTINATION lib
                    LIBRARY   DESTINATION lib
                    RUNTIME   DESTINATION bin
                    FRAMEWORK DESTINATION bin)
        endif()
    endif()
endif()

message(STATUS "CMAKE_CXX_FLAGS: ${CMAKE_CXX_FLAGS}")


include(bundle_static_library.cmake)

set(my_extra_lib)

if(APPLE AND arm64 IN_LIST CMAKE_OSX_ARCHITECTURES AND x86_64 IN_LIST CMAKE_OSX_ARCHITECTURES)
  set(my_extra_lib onnxruntime_mlas_arm64 onnxruntime_mlas_x86_64)
endif()

bundle_static_library(${PROJECT_NAME}
    ${my_extra_lib}
    onnxruntime_session
    onnxruntime_optimizer
    onnxruntime_providers
    onnxruntime_util
    onnxruntime_framework
    onnxruntime_graph
    onnxruntime_mlas
    onnxruntime_common
    onnxruntime_flatbuffers
    onnx_test_data_proto
    onnx
    onnx_proto
    libprotobuf-lite
    re2
    absl_base
    absl_throw_delegate
    absl_raw_hash_set
    absl_hash
    absl_city
    absl_low_level_hash
    cpuinfo
)

file(GLOB _session_headers ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/*.h)
file(GLOB _framework_headers ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/framework/*.h)
file(GLOB _cpu_provider_headers ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/providers/cpu/*.h)

install(FILES ${_session_headers} ${_framework_headers} ${_cpu_provider_headers} TYPE INCLUDE)

if(APPLE)
  file(GLOB _coreml_headers ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/providers/coreml/*.h)
  install(FILES ${_coreml_headers} TYPE INCLUDE)
endif()

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${PROJECT_NAME}${CMAKE_STATIC_LIBRARY_SUFFIX}
    RENAME ${CMAKE_STATIC_LIBRARY_PREFIX}onnxruntime${CMAKE_STATIC_LIBRARY_SUFFIX}
    TYPE LIB
)
