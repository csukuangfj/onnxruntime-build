if (CMAKE_VERSION VERSION_GREATER_EQUAL "4.0.0")
  set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
endif()
cmake_minimum_required(VERSION 3.28)
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.4" CACHE STRING "Minimum OS X deployment version. Used only for macOS")
project(onnxruntime_static_lib)

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(ONNX_USE_MSVC_STATIC_RUNTIME ON)
set(protobuf_MSVC_STATIC_RUNTIME ON)
set(ABSL_MSVC_STATIC_RUNTIME ON)
set(onnxruntime_BUILD_SHARED_LIB OFF)

# if(NOT BUILD_SHARED_LIBS AND MSVC)
#   # see https://cmake.org/cmake/help/latest/prop_tgt/MSVC_RUNTIME_LIBRARY.html
#   # https://stackoverflow.com/questions/14172856/compile-with-mt-instead-of-md-using-cmake
#   if(MSVC)
#       add_compile_options(
#           $<$<CONFIG:>:/MT> #---------|
#           $<$<CONFIG:Debug>:/MTd> #---|-- Statically link the runtime libraries
#           $<$<CONFIG:Release>:/MT> #--|
#           $<$<CONFIG:RelWithDebInfo>:/MT>
#           $<$<CONFIG:MinSizeRel>:/MT>
#       )
#   endif()
# endif()

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
