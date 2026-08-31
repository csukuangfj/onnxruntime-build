cmake_minimum_required(VERSION 3.28)
project(onnxruntime_test CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ONNXRUNTIME_LIB_DIR "" CACHE PATH "Path to the directory containing the onnxruntime static library")
set(ONNXRUNTIME_INCLUDE_DIR "" CACHE PATH "Path to the directory containing onnxruntime headers")

add_executable(test_onnxruntime test_onnxruntime.cc)

target_include_directories(test_onnxruntime PRIVATE ${ONNXRUNTIME_INCLUDE_DIR})

find_library(ONNXRUNTIME_LIB onnxruntime PATHS ${ONNXRUNTIME_LIB_DIR} NO_DEFAULT_PATH)
if(NOT ONNXRUNTIME_LIB)
  message(FATAL_ERROR "Could not find onnxruntime library in ${ONNXRUNTIME_LIB_DIR}")
endif()

target_link_libraries(test_onnxruntime PRIVATE ${ONNXRUNTIME_LIB})

if(WIN32)
  target_link_libraries(test_onnxruntime PRIVATE bcrypt)
elseif(UNIX AND NOT APPLE)
  target_link_libraries(test_onnxruntime PRIVATE pthread dl m)
endif()

enable_testing()
add_test(NAME test_onnxruntime COMMAND test_onnxruntime)
