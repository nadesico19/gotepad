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

# KataGo is embedded into the existing Go GDExtension only on Android. Desktop
# builds keep using the replaceable external-process transport and therefore
# neither compile nor register the embedded engine.
option(BUILD_EMBEDDED_KATAGO
       "Build the embedded KataGo Eigen GDExtension" ${ANDROID})
option(BUILD_ANDROID_KATAGO_OPENCL
       "Build the isolated Android KataGo OpenCL backend" ${ANDROID})
set(KATAGO_SOURCE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/katago/source/KataGo-1.17.1"
    CACHE PATH "Root of the KataGo 1.17.1 source archive")
set(KATAGO_EIGEN_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/katago/source/eigen-3.4.0"
    CACHE PATH "Root of the Eigen 3.4.0 source archive")
set(KATAGO_OPENCL_HEADERS_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/katago/source/OpenCL-Headers-2024.10.24"
    CACHE PATH "Root of the Khronos OpenCL-Headers source archive")

if (BUILD_EMBEDDED_KATAGO)
  if (NOT ANDROID)
    message(FATAL_ERROR
        "BUILD_EMBEDDED_KATAGO is supported only for Android builds")
  endif ()
  set(KATAGO_CPP_DIR "${KATAGO_SOURCE_DIR}/cpp")
  if (NOT EXISTS "${KATAGO_CPP_DIR}/command/analysis.cpp")
    message(FATAL_ERROR
        "KataGo source is missing. Follow third_party/katago/gotepad_info.txt")
  endif ()
  if (NOT EXISTS "${KATAGO_CPP_DIR}/main.h" OR
      NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/katago/embedded-analysis-api.patch")
    message(FATAL_ERROR "KataGo embedded analysis adapter is missing")
  endif ()
  file(READ "${KATAGO_CPP_DIR}/main.h" KATAGO_MAIN_HEADER)
  if (NOT KATAGO_MAIN_HEADER MATCHES "analysisEmbedded")
    message(FATAL_ERROR
        "KataGo source needs embedded-analysis-api.patch; see gotepad_info.txt")
  endif ()
  if (NOT EXISTS "${KATAGO_EIGEN_DIR}/Eigen/Core")
    message(FATAL_ERROR
        "Eigen 3.4.0 is missing. Follow third_party/katago/gotepad_info.txt")
  endif ()

  set(KATAGO_EMBEDDED_COMMON_SOURCES
      core/global.cpp core/base64.cpp core/bsearch.cpp core/commandloop.cpp
      core/config_parser.cpp core/datetime.cpp core/elo.cpp core/fancymath.cpp
      core/fileutils.cpp core/hash.cpp core/logger.cpp core/mainargs.cpp
      core/makedir.cpp core/md5.cpp core/multithread.cpp core/parallel.cpp
      core/rand.cpp core/rand_helpers.cpp core/sha2.cpp core/test.cpp
      core/threadsafecounter.cpp core/threadsafequeue.cpp core/timer.cpp
      game/board.cpp game/rules.cpp game/boardhistory.cpp game/graphhash.cpp
      dataio/sgf.cpp dataio/numpywrite.cpp dataio/poswriter.cpp
      dataio/trainingwrite.cpp dataio/loadmodel.cpp dataio/homedata.cpp
      dataio/files.cpp
      neuralnet/nninputs.cpp neuralnet/sgfmetadata.cpp
      neuralnet/modelversion.cpp neuralnet/nneval.cpp neuralnet/desc.cpp
      neuralnet/debugprint.cpp
      search/timecontrols.cpp search/searchparams.cpp search/mutexpool.cpp
      search/search.cpp search/searchnode.cpp search/searchresults.cpp
      search/searchhelpers.cpp search/searchexplorehelpers.cpp
      search/searchmirror.cpp search/searchmultithreadhelpers.cpp
      search/searchnnhelpers.cpp search/searchtimehelpers.cpp
      search/searchupdatehelpers.cpp search/asyncbot.cpp
      search/distributiontable.cpp search/localpattern.cpp
      search/searchnodetable.cpp search/subtreevaluebiastable.cpp
      search/evalcache.cpp search/patternbonustable.cpp search/analysisdata.cpp
      search/reportedsearchvalues.cpp
      program/gtpconfig.cpp program/setup.cpp program/playutils.cpp
      program/playsettings.cpp program/play.cpp
      command/commandline.cpp command/analysis.cpp)
  list(TRANSFORM KATAGO_EMBEDDED_COMMON_SOURCES
       PREPEND "${KATAGO_CPP_DIR}/")
  set(KATAGO_EMBEDDED_EIGEN_SOURCES
      ${KATAGO_EMBEDDED_COMMON_SOURCES}
      "${KATAGO_CPP_DIR}/neuralnet/eigenbackend.cpp")

  find_package(Threads REQUIRED)
  find_package(ZLIB REQUIRED)
  set(KATAGO_GDEXT_SOURCES
      src/katago_gdext.cpp src/katago_version.cpp
      ${KATAGO_EMBEDDED_EIGEN_SOURCES})
  target_sources(go_gdext PRIVATE ${KATAGO_GDEXT_SOURCES})
  target_include_directories(go_gdext PRIVATE
      "${KATAGO_CPP_DIR}"
      "${KATAGO_CPP_DIR}/external"
      "${KATAGO_CPP_DIR}/external/tclap-1.2.5/include"
      "${KATAGO_CPP_DIR}/external/filesystem-1.5.8/include"
      "${KATAGO_EIGEN_DIR}")
  target_compile_definitions(go_gdext PRIVATE GOTEPAD_KATAGO_MERGED)
  set_property(SOURCE ${KATAGO_GDEXT_SOURCES} APPEND PROPERTY
      COMPILE_DEFINITIONS
      GOTEPAD_KATAGO_EMBEDDED GOTEPAD_KATAGO_MERGED
      USE_EIGEN_BACKEND NO_GIT_REVISION NO_LIBZIP
      BYTE_ORDER=1234 LITTLE_ENDIAN=1234 BIG_ENDIAN=4321)
  set_property(SOURCE ${KATAGO_GDEXT_SOURCES} APPEND PROPERTY
      COMPILE_OPTIONS -fsigned-char)
  target_link_libraries(go_gdext PRIVATE Threads::Threads ZLIB::ZLIB)
  # Android's NDK does not expose the legacy endian macros expected by
  # KataGo's portable SHA implementation. Gotepad currently builds only
  # little-endian arm64 Android packages.
  target_link_libraries(go_gdext PRIVATE log android)
  target_link_options(go_gdext PRIVATE
       "-Wl,-z,max-page-size=16384")

  if (BUILD_ANDROID_KATAGO_OPENCL)
    if (NOT EXISTS "${KATAGO_OPENCL_HEADERS_DIR}/CL/cl.h")
      message(FATAL_ERROR
          "Khronos OpenCL-Headers are missing; see third_party/katago/gotepad_info.txt")
    endif ()

    # The NDK does not ship an OpenCL import library. This link-only stub gives
    # the backend a dependency on the device-provided libOpenCL.so. It is kept
    # in the CMake build directory and must never be packaged in the APK.
    add_library(android_opencl_link_stub SHARED
        src/android_opencl_link_stub.cpp)
    target_include_directories(android_opencl_link_stub PRIVATE
        "${KATAGO_OPENCL_HEADERS_DIR}")
    set_target_properties(android_opencl_link_stub PROPERTIES
        OUTPUT_NAME OpenCL
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/opencl-link-only")

    set(KATAGO_OPENCL_SOURCES
        ${KATAGO_EMBEDDED_COMMON_SOURCES}
        "${KATAGO_CPP_DIR}/neuralnet/openclbackend.cpp"
        "${KATAGO_CPP_DIR}/neuralnet/openclkernels.cpp"
        "${KATAGO_CPP_DIR}/neuralnet/openclhelpers.cpp"
        "${KATAGO_CPP_DIR}/neuralnet/opencltuner.cpp")
    add_library(katago_opencl_android SHARED
        src/katago_android_opencl_jni.cpp
        src/katago_version.cpp
        ${KATAGO_OPENCL_SOURCES})
    target_include_directories(katago_opencl_android PRIVATE
        "${KATAGO_CPP_DIR}"
        "${KATAGO_CPP_DIR}/external"
        "${KATAGO_CPP_DIR}/external/tclap-1.2.5/include"
        "${KATAGO_CPP_DIR}/external/filesystem-1.5.8/include"
        "${KATAGO_OPENCL_HEADERS_DIR}")
    target_compile_definitions(katago_opencl_android PRIVATE
        GOTEPAD_KATAGO_EMBEDDED USE_OPENCL_BACKEND
        NO_GIT_REVISION NO_LIBZIP
        BYTE_ORDER=1234 LITTLE_ENDIAN=1234 BIG_ENDIAN=4321)
    target_compile_options(katago_opencl_android PRIVATE
        -fsigned-char -fvisibility=hidden)
    target_link_libraries(katago_opencl_android PRIVATE
        Threads::Threads ZLIB::ZLIB log android android_opencl_link_stub)
    target_link_options(katago_opencl_android PRIVATE
        "-Wl,-z,max-page-size=16384")
    set_target_properties(katago_opencl_android PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/android-opencl-output")
    add_custom_command(TARGET katago_opencl_android POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/android/build/libs/$<LOWER_CASE:$<CONFIG>>/arm64-v8a"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "$<TARGET_FILE:katago_opencl_android>"
            "${CMAKE_CURRENT_SOURCE_DIR}/gotepad-gd/android/build/libs/$<LOWER_CASE:$<CONFIG>>/arm64-v8a/libkatago_opencl_android.so")
  endif ()
endif ()

if (WIN32)
  add_executable(test_goban_gui WIN32
      tests/test_goban_gui.cpp
      src/go_core.hpp)
  target_link_libraries(test_goban_gui PRIVATE user32 gdi32 ${GOBAN_SGF_LIBRARY})
endif ()
