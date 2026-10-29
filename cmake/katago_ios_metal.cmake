# Build the existing MPSGraph GPU backend without the macOS Core ML converter
# and its host protobuf/abseil dependencies. ANE selection fails explicitly.
file(READ "${KATAGO_CPP_DIR}/neuralnet/metalbackend.swift" katago_ios_swift_source)
file(READ "${KATAGO_CPP_DIR}/command/analysis.cpp" katago_ios_analysis_source)
if (NOT katago_ios_swift_source MATCHES "MPSGraphModelSession" OR
    NOT katago_ios_analysis_source MATCHES "run_metal_nn_benchmark")
  message(FATAL_ERROR "KataGo iOS source needs third_party/katago/ios.patch")
endif ()
set(katago_ios_triple "arm64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(CMAKE_Swift_FLAGS "-target ${katago_ios_triple}" CACHE STRING "Swift iOS target" FORCE)
enable_language(Swift)
execute_process(COMMAND xcrun --find swiftc
    OUTPUT_VARIABLE katago_xcode_swift_compiler OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY)
get_filename_component(katago_swift_bin_directory "${katago_xcode_swift_compiler}" DIRECTORY)
get_filename_component(katago_swift_runtime_directory
    "${katago_swift_bin_directory}/../lib/swift/iphoneos" ABSOLUTE)
set(katago_swift_sources
    "${KATAGO_CPP_DIR}/neuralnet/metalbackend.swift"
    "${KATAGO_CPP_DIR}/neuralnet/metallayers.swift")
set(katago_swift_header "${CMAKE_CURRENT_BINARY_DIR}/include/KataGoSwift/KataGoSwift-swift.h")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/KataGoSwift")
add_custom_command(OUTPUT "${katago_swift_header}"
    COMMAND "${CMAKE_Swift_COMPILER}" -typecheck ${katago_swift_sources}
        -sdk "${CMAKE_OSX_SYSROOT}" -target "${katago_ios_triple}"
        -swift-version 5 -module-name KataGoSwift
        -cxx-interoperability-mode=default
        -emit-clang-header-path "${katago_swift_header}"
    DEPENDS ${katago_swift_sources} VERBATIM)
add_library(KataGoSwift STATIC ${katago_swift_sources} "${katago_swift_header}")
set_target_properties(KataGoSwift PROPERTIES Swift_MODULE_NAME KataGoSwift Swift_LANGUAGE_VERSION 5)
target_compile_options(KataGoSwift PRIVATE -cxx-interoperability-mode=default)

# Generate an iOS adapter in the build tree, leaving vendored sources intact.
file(READ "${KATAGO_CPP_DIR}/neuralnet/metalbackend.cpp" katago_metal_source)
string(REPLACE "#include <katagocoreml/KataGoConverter.hpp>" "" katago_metal_source "${katago_metal_source}")
string(REPLACE "katagocoreml::KataGoConverter::wouldBuildFullyFp32(\n    modelDesc->trunk.trunkNumChannels, trunkHasTransformerBlocks(modelDesc->trunk.blocks))"
    "false" katago_metal_source "${katago_metal_source}")
string(FIND "${katago_metal_source}" "namespace CoreMLConversion {" conversion_start)
string(FIND "${katago_metal_source}" "}  // namespace CoreMLConversion" conversion_end)
if (conversion_start LESS 0 OR conversion_end LESS conversion_start)
  message(FATAL_ERROR "KataGo Metal converter markers changed; review the iOS adapter")
endif ()
string(LENGTH "}  // namespace CoreMLConversion" conversion_end_length)
math(EXPR conversion_end "${conversion_end} + ${conversion_end_length}")
string(SUBSTRING "${katago_metal_source}" 0 ${conversion_start} metal_prefix)
string(SUBSTRING "${katago_metal_source}" ${conversion_end} -1 metal_suffix)
set(metal_gpu_conversion [=[
namespace CoreMLConversion {
static string convertModelToTemp(const string&, int, int, bool, bool, int, int) {
  throw runtime_error("Gotepad iOS supports Metal GPU/MPSGraph; ANE conversion is unavailable");
}
}
]=])
set(KATAGO_IOS_METAL_SOURCE "${CMAKE_CURRENT_BINARY_DIR}/katago_ios_metal_backend.cpp")
file(CONFIGURE OUTPUT "${KATAGO_IOS_METAL_SOURCE}"
    CONTENT "${metal_prefix}${metal_gpu_conversion}${metal_suffix}" @ONLY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${KATAGO_CPP_DIR}/neuralnet/metalbackend.cpp")
