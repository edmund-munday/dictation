cmake_minimum_required(VERSION 3.22.1)
project(dictation_whisper)

set(WHISPER_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/whisper.cpp")
if(NOT EXISTS "${WHISPER_SRC}/CMakeLists.txt")
    message(FATAL_ERROR "whisper.cpp missing at ${WHISPER_SRC}. The Gradle fetchWhisperCpp task should have cloned it.")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_IS_DEV OFF CACHE BOOL "" FORCE)

# 16 KB page devices require every LOAD segment to be aligned to 0x4000.
string(APPEND CMAKE_SHARED_LINKER_FLAGS " -Wl,-z,max-page-size=16384")

add_subdirectory("${WHISPER_SRC}" whisper-build EXCLUDE_FROM_ALL)

add_library(dictation_whisper SHARED whisper_jni.cpp)
target_link_options(dictation_whisper PRIVATE "-Wl,-z,max-page-size=16384")
target_link_libraries(dictation_whisper whisper log)
target_include_directories(dictation_whisper PRIVATE "${WHISPER_SRC}/include")
