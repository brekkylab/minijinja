# ==============================================================================
# MiniJinja C Bindings - CMake Configuration
# ==============================================================================

cmake_minimum_required(VERSION 3.15)

# ==============================================================================
# Project Configuration
# ==============================================================================

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

# ==============================================================================
# Build Options
# ==============================================================================

option(MINIJINJA_CONTRIB_ENABLED      "Enable minijinja-contrib"                ON)
option(MINIJINJA_BUILD_SHARED         "Build shared library"                    OFF)
option(MINIJINJA_INSTALL              "Install the library"                     OFF)
option(MINIJINJA_RUST_NIGHTLY         "Use nightly toolchain for Rust target"   OFF)
option(MINIJINJA_RUST_FLAGS           "RUSTFLAGS to use on building minijinja"  "")
option(MINIJINJA_CARGO_BUILD_FLAGS    "cargo build flags to use on building"    "")

# ==============================================================================
# Platform Detection & Rust Configuration
# ==============================================================================

# Platform and architecture detection for Rust target
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/minijinjaRustTargets.cmake)

# Detect Rust toolchain
find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_program(RUSTC_EXECUTABLE rustc REQUIRED)

# Validate Rust installation
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

# ==============================================================================
# Build Configuration
# ==============================================================================

# Set build configuration
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CARGO_BUILD_TYPE "debug")
else()
    set(CARGO_BUILD_TYPE "release")
    list(APPEND MINIJINJA_CARGO_BUILD_FLAGS "--release")
endif()

# Determine output paths
set(CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/target")
set(RUST_LIB_DIR "${CARGO_TARGET_DIR}/${MINIJINJA_RUST_TARGET}/${CARGO_BUILD_TYPE}")

# ==============================================================================
# Library Naming Configuration
# ==============================================================================

if(MINIJINJA_BUILD_SHARED)
    # Shared library names
    if(WIN32)
        set(RUST_LIB_NAME "minijinja_cabi.dll")
        set(RUST_LIB_IMPORT "minijinja_cabi.dll.lib")
    elseif(APPLE)
        set(RUST_LIB_NAME "libminijinja_cabi.dylib")
    else()
        set(RUST_LIB_NAME "libminijinja_cabi.so")
    endif()
else()
    # Static library names
    if(WIN32)
        set(RUST_LIB_NAME "minijinja_cabi.lib")
    else()
        set(RUST_LIB_NAME "libminijinja_cabi.a")
    endif()
endif()

set(RUST_LIB_PATH "${RUST_LIB_DIR}/${RUST_LIB_NAME}")

# ==============================================================================
# Rust Target Installation
# ==============================================================================

# Prepare rustup target flags
set(RUSTUP_TARGET_FLAGS "")
if(MINIJINJA_RUST_NIGHTLY)
    list(APPEND RUSTUP_TARGET_FLAGS "--toolchain=nightly")
endif()

# Install Rust target if needed
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/rust_target_check.stamp
    COMMAND rustup target add ${MINIJINJA_RUST_TARGET} ${RUSTUP_TARGET_FLAGS}
    COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/rust_target_check.stamp
    COMMENT "Installing Rust target: ${MINIJINJA_RUST_TARGET}"
    VERBATIM
)

# ==============================================================================
# Cargo Build Environment
# ==============================================================================

# Set up environment variables for cargo
set(CARGO_ENV_VARS "CARGO_TARGET_DIR=${CARGO_TARGET_DIR}")

# Cross-compilation environment
if(CMAKE_CROSSCOMPILING)
    list(APPEND CARGO_ENV_VARS ${MINIJINJA_CROSS_COMPILE_ENV})
endif()

# Custom Rust flags
if(NOT MINIJINJA_RUST_FLAGS STREQUAL "")
    list(APPEND CARGO_ENV_VARS "RUSTFLAGS=${MINIJINJA_RUST_FLAGS}")
endif()

# Prepare cargo build flags
list(APPEND MINIJINJA_CARGO_BUILD_FLAGS "--target=${MINIJINJA_RUST_TARGET}")

# Add crate type flag
if(MINIJINJA_BUILD_SHARED)
    list(APPEND MINIJINJA_CARGO_BUILD_FLAGS "--crate-type=cdylib")
else()
    list(APPEND MINIJINJA_CARGO_BUILD_FLAGS "--crate-type=staticlib")
endif()

# Add contrib features
if(MINIJINJA_CONTRIB_ENABLED)
    list(APPEND MINIJINJA_CARGO_BUILD_FLAGS "--features=contrib")
endif()

# ==============================================================================
# Cargo Build Command
# ==============================================================================

set(CARGO_BUILD_USE_NIGHTLY "")
if(MINIJINJA_RUST_NIGHTLY)
    set(CARGO_BUILD_USE_NIGHTLY "+nightly")
endif()

# Build the cargo command list
set(CARGO_BUILD_COMMAND
    ${CMAKE_COMMAND} -E env ${CARGO_ENV_VARS}
    ${CARGO_EXECUTABLE} ${CARGO_BUILD_USE_NIGHTLY} rustc
    ${MINIJINJA_CARGO_BUILD_FLAGS}
)

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

# ==============================================================================
# Library Target Configuration
# ==============================================================================

# Create interface library
add_library(cabi INTERFACE)

# Add dependency on the Rust build
add_dependencies(cabi cabi-rust)

# Configure include directories
target_include_directories(cabi INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Configure linking
target_link_libraries(cabi INTERFACE
    ${RUST_LIB_PATH}
    ${MINIJINJA_SYSTEM_LIBS}
)

# Platform-specific compile definitions
if(WIN32)
    target_compile_definitions(cabi INTERFACE
        WIN32_LEAN_AND_MEAN
        NOMINMAX
    )
endif()

# Create alias target
add_library(minijinja::cabi ALIAS cabi)

# ==============================================================================
# Installation Configuration
# ==============================================================================

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

    # Install Windows import library if needed
    if(WIN32 AND MINIJINJA_BUILD_SHARED AND RUST_LIB_IMPORT)
        install(FILES "${RUST_LIB_DIR}/${RUST_LIB_IMPORT}"
            DESTINATION ${CMAKE_INSTALL_LIBDIR}
            COMPONENT Development
        )
    endif()

    # Install targets
    install(TARGETS cabi
        EXPORT minijinja-targets
    )

    # Configure package config files
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

    # Install config files
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfig.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/minijinjaConfigVersion.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/minijinja
        COMPONENT Development
    )

    # Install export targets
    install(EXPORT minijinja-targets
        FILE minijinjaTargets.cmake
        NAMESPACE minijinja::
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/minijinja"
        COMPONENT Development
    )
endif()
