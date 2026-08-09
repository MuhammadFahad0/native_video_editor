cmake_minimum_required(VERSION 3.14)
project(native_video_editor_plugin LANGUAGES CXX)

set(PLUGIN_NAME native_video_editor_plugin)

add_library(${PLUGIN_NAME} SHARED
  "include/native_video_editor/native_video_editor_plugin_c_api.h"
  "native_video_editor_plugin_c_api.cpp"
  "native_video_editor_plugin.h"
  "native_video_editor_plugin.cpp"
)

apply_standard_cpp_compiler_flags(${PLUGIN_NAME})

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

target_compile_options(${PLUGIN_NAME} PRIVATE /await:strict /std:c++17)
target_link_libraries(${PLUGIN_NAME} PRIVATE windowsapp)

set(native_video_editor_public_headers
  "include/native_video_editor/native_video_editor_plugin_c_api.h"
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  PUBLIC_HEADER "${native_video_editor_public_headers}"
)
