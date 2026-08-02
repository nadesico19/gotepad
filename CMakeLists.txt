cmake_minimum_required(VERSION 3.20)
project(goban)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if (MSVC)
  add_compile_options(/utf-8)
  # godot-cpp links the static MSVC runtime by default. Set this before
  # creating third-party targets so every library linked into the extension
  # uses the same runtime.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded" CACHE STRING
      "MSVC runtime library used by all project targets")
endif ()

set(ENABLE_DEFAULT NO)
set(ENABLE_SHARED_LIBRARY NO)
set(ENABLE_STATIC_LIBRARY YES)
set(ENABLE_SHARED_FRAMEWORK NO)
set(ENABLE_STATIC_FRAMEWORK NO)
set(ENABLE_TESTS NO)
set(ENABLE_EXAMPLES NO)

add_subdirectory(third_party/libsgfcplusplus EXCLUDE_FROM_ALL)

add_library(goban_miniz STATIC
    third_party/miniz/miniz.c
    third_party/miniz/miniz_tdef.c
    third_party/miniz/miniz_tinfl.c
    third_party/miniz/miniz_zip.c)
target_include_directories(goban_miniz PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/miniz)
set_target_properties(goban_miniz PROPERTIES POSITION_INDEPENDENT_CODE ON)

set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL
    "Do not build LunaSVG examples" FORCE)
set(USE_SYSTEM_PLUTOVG OFF CACHE BOOL
    "Use the bundled PlutoVG required by LunaSVG" FORCE)
add_subdirectory(third_party/lunasvg EXCLUDE_FROM_ALL)
set_target_properties(lunasvg plutovg PROPERTIES POSITION_INDEPENDENT_CODE ON)

set(GODOTCPP_TARGET "template_debug" CACHE STRING
    "Godot target used to build the GDExtension")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING
    "Godot API version used to generate C++ bindings")
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL
    "Keep exceptions enabled because GoCore validates with exceptions")
set(GODOTCPP_SYSTEM_HEADERS ON CACHE BOOL
    "Treat bundled godot-cpp headers as system headers")
add_subdirectory(third_party/godot-cpp EXCLUDE_FROM_ALL)

if (WIN32)
  target_compile_definitions(libsgfcplusplus_static_objects PRIVATE WINICONV_CONST=)
endif ()

set(GOBAN_SGF_LIBRARY libsgfcplusplus_static)

function(target_link_goban_dependencies target_name)
  target_link_libraries(${target_name} PRIVATE ${GOBAN_SGF_LIBRARY})
  target_include_directories(${target_name} PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libsgfcplusplus/include
      ${CMAKE_CURRENT_BINARY_DIR}/third_party/libsgfcplusplus/src)
endfunction()

add_executable(test_placement
    tests/test_placement.cpp
    src/go_core.hpp
    src/go_notes.hpp)
target_link_goban_dependencies(test_placement)

add_executable(test_roaming
    tests/test_roaming.cpp
    src/go_core.hpp)
target_link_goban_dependencies(test_roaming)

add_executable(test_cursor
    tests/test_cursor.cpp
    src/go_core.hpp)
target_link_goban_dependencies(test_cursor)

add_executable(test_sgf
    tests/test_sgf.cpp
    src/go_notes_sgf.cpp
    src/go_notes_sgf_save.cpp
    src/go_notes_pptx.cpp
    src/go_core.hpp
    src/go_notes.hpp)
target_link_libraries(test_sgf PRIVATE goban_miniz lunasvg::lunasvg)
target_link_goban_dependencies(test_sgf)

add_executable(test_pptx
    tests/test_pptx.cpp
    src/go_notes_pptx.cpp
    src/go_core.hpp
    src/go_notes.hpp)
target_link_libraries(test_pptx PRIVATE goban_miniz lunasvg::lunasvg)
target_link_goban_dependencies(test_pptx)

add_library(go_gdext SHARED
    src/go_gdext.cpp
    src/go_notes_sgf.cpp
    src/go_notes_sgf_save.cpp
    src/go_notes_pptx.cpp
    src/go_core.hpp
    src/go_notes.hpp)
target_link_libraries(go_gdext PRIVATE godot::cpp goban_miniz lunasvg::lunasvg)
target_link_goban_dependencies(go_gdext)
get_target_property(GOBAN_GDEXT_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(go_gdext PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
    PREFIX "lib"
    OUTPUT_NAME "go_gdext${GOBAN_GDEXT_SUFFIX}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    LIBRARY_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin"
    LIBRARY_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/bin")

if (WIN32)
  add_executable(test_goban_gui WIN32
      tests/test_goban_gui.cpp
      src/go_core.hpp)
  target_link_libraries(test_goban_gui PRIVATE user32 gdi32 ${GOBAN_SGF_LIBRARY})
endif ()
