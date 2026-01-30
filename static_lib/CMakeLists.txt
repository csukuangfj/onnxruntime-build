if (CMAKE_VERSION VERSION_GREATER_EQUAL "4.0.0")
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
endif()
cmake_minimum_required(VERSION 3.28)

# https://cmake.org/cmake/help/latest/prop_tgt/MSVC_RUNTIME_LIBRARY.html
cmake_policy(SET CMP0091 NEW)

set(CMAKE_OSX_DEPLOYMENT_TARGET "13.4" CACHE STRING "Minimum OS X deployment version. Used only for macOS")
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

set(FILES_TO_INSTALL
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_float16.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_c_api.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_ep_c_api.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_ep_device_ep_metadata_keys.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_lite_custom_op.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_cxx_api.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_cxx_inline.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/providers/cpu/cpu_provider_factory.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_run_options_config_keys.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/session/onnxruntime_session_options_config_keys.h
    ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/framework/provider_options.h
)
foreach(FILE_PATH IN LISTS FILES_TO_INSTALL)
  if(EXISTS "${FILE_PATH}")
    install(
        FILES
        ${FILE_PATH}
        TYPE INCLUDE
    )
  endif()
endforeach()

if(APPLE)
  install(
      FILES
      ${ONNXRUNTIME_SOURCE_DIR}/include/onnxruntime/core/providers/coreml/coreml_provider_factory.h
      TYPE INCLUDE
  )
endif()

install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}${PROJECT_NAME}${CMAKE_STATIC_LIBRARY_SUFFIX}
    RENAME ${CMAKE_STATIC_LIBRARY_PREFIX}onnxruntime${CMAKE_STATIC_LIBRARY_SUFFIX}
    TYPE LIB
)
