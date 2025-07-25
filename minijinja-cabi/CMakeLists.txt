cmake_minimum_required(VERSION 3.15)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/minijinjaGetVersion.cmake")

project(minijinja
    VERSION ${MINIJINJA_VERSION}
    DESCRIPTION "C bindings for MiniJinja template engine"
    LANGUAGES C CXX
)

# Set policies for better compatibility
if(POLICY CMP0077)
    cmake_policy(SET CMP0077 NEW)
endif()

if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()

# Options
option(MINIJINJA_CONTRIB_ENABLED "Enable minijinja-contrib" ON)
option(MINIJINJA_BUILD_SHARED "Build shared library" OFF)
option(MINIJINJA_INSTALL "Install the library" OFF)

# Platform and architecture detection for Rust target
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/minijinjaRustTargets.cmake)

# Detect Rust toolchain
find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_program(RUSTC_EXECUTABLE rustc REQUIRED)

# Get Rust version for validation
execute_process(
    COMMAND ${RUSTC_EXECUTABLE} --version
    OUTPUT_VARIABLE RUST_VERSION_OUTPUT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE RUST_VERSION_RESULT
)

if(NOT RUST_VERSION_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to get Rust version")
endif()

message(STATUS "Rust version: ${RUST_VERSION_OUTPUT}")

# Set build configuration
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CARGO_BUILD_TYPE "debug")
else()
    set(CARGO_BUILD_TYPE "release")
    set(CARGO_BUILD_FLAGS "--release")
endif()

# Determine output paths
set(CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/target")
set(RUST_LIB_DIR "${CARGO_TARGET_DIR}/${MINIJINJA_RUST_TARGET}/${CARGO_BUILD_TYPE}")

if(MINIJINJA_BUILD_SHARED)
    if(WIN32)
        set(RUST_LIB_NAME "minijinja_cabi.dll")
        set(RUST_LIB_IMPORT "minijinja_cabi.dll.lib")
    elseif(APPLE)
        set(RUST_LIB_NAME "libminijinja_cabi.dylib")
    else()
        set(RUST_LIB_NAME "libminijinja_cabi.so")
    endif()
else()
    if(WIN32)
        set(RUST_LIB_NAME "minijinja_cabi.lib")
    else()
        set(RUST_LIB_NAME "libminijinja_cabi.a")
    endif()
endif()

set(RUST_LIB_PATH "${RUST_LIB_DIR}/${RUST_LIB_NAME}")

# Set up environment for cross-compilation
set(CARGO_ENV_VARS "CARGO_TARGET_DIR=${CARGO_TARGET_DIR}")

if(CMAKE_CROSSCOMPILING)
    list(APPEND CARGO_ENV_VARS ${MINIJINJA_CROSS_COMPILE_ENV})
endif()

# Install Rust target if needed
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/rust_target_check.stamp
    COMMAND rustup target add ${MINIJINJA_RUST_TARGET}
    COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/rust_target_check.stamp
    COMMENT "Installing Rust target: ${MINIJINJA_RUST_TARGET}"
    VERBATIM
)

if(MINIJINJA_CONTRIB_ENABLED)
    list(APPEND CARGO_BUILD_FLAGS "--features=contrib")
endif()

# Build the cargo command list
set(CARGO_BUILD_COMMAND
    ${CMAKE_COMMAND} -E env ${CARGO_ENV_VARS}
    ${CARGO_EXECUTABLE} rustc
    --target=${MINIJINJA_RUST_TARGET}
    ${CARGO_BUILD_FLAGS}
)

# Add crate type flag only for shared libraries
if(MINIJINJA_BUILD_SHARED)
    list(APPEND CARGO_BUILD_COMMAND "--crate-type=cdylib")
else()
    list(APPEND CARGO_BUILD_COMMAND "--crate-type=staticlib")
endif()

# Custom command to build the Rust library
add_custom_command(
    OUTPUT ${RUST_LIB_PATH}
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/rust_target_check.stamp
    COMMAND ${CARGO_BUILD_COMMAND}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building minijinja for ${MINIJINJA_RUST_TARGET} (${CARGO_BUILD_TYPE})"
    VERBATIM
)

# Create custom target for the build
add_custom_target(cabi-rust
    ALL
    DEPENDS ${RUST_LIB_PATH}
)

add_library(cabi INTERFACE)

# Add dependency on the Rust build
add_dependencies(cabi cabi-rust)

target_include_directories(cabi INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Platform-specific linking
target_link_libraries(cabi INTERFACE
    ${RUST_LIB_PATH}
    ${MINIJINJA_SYSTEM_LIBS}
)

# Add platform-specific compile definitions
if(WIN32)
    target_compile_definitions(cabi INTERFACE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
endif()


# Create alias target
add_library(minijinja::cabi ALIAS cabi)

# Installation
if(MINIJINJA_INSTALL)
    include(GNUInstallDirs)
    include(CMakePackageConfigHelpers)

    # Install headers
    install(DIRECTORY include/
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
        FILES_MATCHING PATTERN "*.h"
    )

    # Install the built library
    install(FILES ${RUST_LIB_PATH}
        DESTINATION ${CMAKE_INSTALL_LIBDIR}
        COMPONENT Runtime
    )

    if(WIN32 AND MINIJINJA_BUILD_SHARED AND RUST_LIB_IMPORT)
        install(FILES "${RUST_LIB_DIR}/${RUST_LIB_IMPORT}"
            DESTINATION ${CMAKE_INSTALL_LIBDIR}
            COMPONENT Development
        )
    endif()

    install(TARGETS cabi
        EXPORT minijinja-targets
    )

    configure_package_config_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/minijinjaConfig.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfig.cmake"
        INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/minijinja
    )

    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfigVersion.cmake"
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion
    )

    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfig.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfigVersion.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/minijinja
        COMPONENT Development
    )

    install(EXPORT minijinja-targets
        FILE minijinjaTargets.cmake
        NAMESPACE minijinja::
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/minijinja"
        COMPONENT Development
    )
endif()

# Status information
message(STATUS "MiniJinja Configuration:")
message(STATUS "  Platform: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  Architecture: ${CMAKE_SYSTEM_PROCESSOR}")
message(STATUS "  Rust Target: ${MINIJINJA_RUST_TARGET}")
message(STATUS "  Build Type: ${CARGO_BUILD_TYPE}")
message(STATUS "  Library Type: ${LIB_TYPE}")
message(STATUS "  Output: ${RUST_LIB_PATH}")
