# Platform and target detection for minijinja

# Detect target architecture
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    set(MINIJINJA_ARCH "x86_64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "i386|i686")
    set(MINIJINJA_ARCH "i686")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
    set(MINIJINJA_ARCH "aarch64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
    set(MINIJINJA_ARCH "armv7")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "riscv64")
    set(MINIJINJA_ARCH "riscv64")
else()
    set(MINIJINJA_ARCH ${CMAKE_SYSTEM_PROCESSOR})
endif()

# Determine Rust target triple
if(EMSCRIPTEN)
    set(MINIJINJA_RUST_TARGET "wasm32-unknown-emscripten")
    set(MINIJINJA_SYSTEM_LIBS "")

    # Emscripten-specific environment
    set(MINIJINJA_CROSS_COMPILE_ENV
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "AR=emar"
        "RANLIB=emranlib"
    )

elseif(WIN32)
    if(MINIJINJA_ARCH STREQUAL "x86_64")
        set(MINIJINJA_RUST_TARGET "x86_64-pc-windows-msvc")
    elseif(MINIJINJA_ARCH STREQUAL "i686")
        set(MINIJINJA_RUST_TARGET "i686-pc-windows-msvc")
    elseif(MINIJINJA_ARCH STREQUAL "aarch64")
        set(MINIJINJA_RUST_TARGET "aarch64-pc-windows-msvc")
    else()
        set(MINIJINJA_RUST_TARGET "x86_64-pc-windows-msvc")
    endif()

    set(MINIJINJA_SYSTEM_LIBS "ws2_32;userenv;bcrypt;ntdll;kernel32;advapi32")
    set(MINIJINJA_CROSS_COMPILE_ENV "")

elseif(APPLE)
    # Handle both macOS and iOS
    if(CMAKE_OSX_DEPLOYMENT_TARGET)
        set(MINIJINJA_MACOS_TARGET ${CMAKE_OSX_DEPLOYMENT_TARGET})
    else()
        set(MINIJINJA_MACOS_TARGET "10.15")
    endif()

    if(IOS)
        if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
            set(MINIJINJA_RUST_TARGET "aarch64-apple-ios")
        else()
            set(MINIJINJA_RUST_TARGET "x86_64-apple-ios")
        endif()
    else()
        if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64" OR MINIJINJA_ARCH STREQUAL "aarch64")
            set(MINIJINJA_RUST_TARGET "aarch64-apple-darwin")
        else()
            set(MINIJINJA_RUST_TARGET "x86_64-apple-darwin")
        endif()
    endif()

    # Find required frameworks
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
    find_library(CORE_FOUNDATION_FRAMEWORK CoreFoundation REQUIRED)

    set(MINIJINJA_SYSTEM_LIBS
        "pthread;dl;m;${SECURITY_FRAMEWORK};${FOUNDATION_FRAMEWORK};${CORE_FOUNDATION_FRAMEWORK}")

    set(MINIJINJA_CROSS_COMPILE_ENV
        "MACOSX_DEPLOYMENT_TARGET=${MINIJINJA_MACOS_TARGET}"
    )

elseif(ANDROID)
    # Android target mapping
    if(ANDROID_ABI STREQUAL "arm64-v8a")
        set(MINIJINJA_RUST_TARGET "aarch64-linux-android")
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
        set(MINIJINJA_RUST_TARGET "armv7-linux-androideabi")
    elseif(ANDROID_ABI STREQUAL "x86_64")
        set(MINIJINJA_RUST_TARGET "x86_64-linux-android")
    elseif(ANDROID_ABI STREQUAL "x86")
        set(MINIJINJA_RUST_TARGET "i686-linux-android")
    else()
        message(FATAL_ERROR "Unsupported Android ABI: ${ANDROID_ABI}")
    endif()

    set(MINIJINJA_SYSTEM_LIBS "log;m")

    # Android NDK environment
    set(MINIJINJA_CROSS_COMPILE_ENV
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "AR=${CMAKE_AR}"
        "RANLIB=${CMAKE_RANLIB}"
        "ANDROID_NDK_ROOT=${CMAKE_ANDROID_NDK}"
    )

    if(CMAKE_ANDROID_API)
        list(APPEND MINIJINJA_CROSS_COMPILE_ENV "ANDROID_API_LEVEL=${CMAKE_ANDROID_API}")
    endif()

else()
    # Linux and other Unix-like systems
    if(MINIJINJA_ARCH STREQUAL "x86_64")
        set(MINIJINJA_RUST_TARGET "x86_64-unknown-linux-gnu")
    elseif(MINIJINJA_ARCH STREQUAL "aarch64")
        set(MINIJINJA_RUST_TARGET "aarch64-unknown-linux-gnu")
    elseif(MINIJINJA_ARCH STREQUAL "armv7")
        set(MINIJINJA_RUST_TARGET "armv7-unknown-linux-gnueabihf")
    elseif(MINIJINJA_ARCH STREQUAL "i686")
        set(MINIJINJA_RUST_TARGET "i686-unknown-linux-gnu")
    elseif(MINIJINJA_ARCH STREQUAL "riscv64")
        set(MINIJINJA_RUST_TARGET "riscv64gc-unknown-linux-gnu")
    else()
        # Default fallback
        set(MINIJINJA_RUST_TARGET "x86_64-unknown-linux-gnu")
    endif()

    set(MINIJINJA_SYSTEM_LIBS "pthread;dl;m;rt")

    # Cross-compilation environment for Linux
    if(CMAKE_CROSSCOMPILING)
        set(MINIJINJA_CROSS_COMPILE_ENV
            "CC=${CMAKE_C_COMPILER}"
            "CXX=${CMAKE_CXX_COMPILER}"
            "AR=${CMAKE_AR}"
            "RANLIB=${CMAKE_RANLIB}"
        )
    else()
        set(MINIJINJA_CROSS_COMPILE_ENV "")
    endif()
endif()

# Special handling for musl libc
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    execute_process(
        COMMAND ${CMAKE_C_COMPILER} -dumpmachine
        OUTPUT_VARIABLE COMPILER_TARGET
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )

    if(COMPILER_TARGET MATCHES "musl")
        string(REPLACE "-gnu" "-musl" MINIJINJA_RUST_TARGET ${MINIJINJA_RUST_TARGET})
    endif()
endif()

# Validate that we have a supported target
set(SUPPORTED_TARGETS
    "x86_64-unknown-linux-gnu"
    "x86_64-unknown-linux-musl"
    "aarch64-unknown-linux-gnu"
    "aarch64-unknown-linux-musl"
    "armv7-unknown-linux-gnueabihf"
    "armv7-unknown-linux-musleabihf"
    "i686-unknown-linux-gnu"
    "riscv64gc-unknown-linux-gnu"
    "x86_64-pc-windows-msvc"
    "i686-pc-windows-msvc"
    "aarch64-pc-windows-msvc"
    "x86_64-apple-darwin"
    "aarch64-apple-darwin"
    "x86_64-apple-ios"
    "aarch64-apple-ios"
    "aarch64-linux-android"
    "armv7-linux-androideabi"
    "x86_64-linux-android"
    "i686-linux-android"
    "wasm32-unknown-emscripten"
    "wasm32-wasi"
)

list(FIND SUPPORTED_TARGETS ${MINIJINJA_RUST_TARGET} TARGET_INDEX)
if(TARGET_INDEX EQUAL -1)
    message(WARNING "Rust target '${MINIJINJA_RUST_TARGET}' may not be supported. Supported targets: ${SUPPORTED_TARGETS}")
endif()

message(STATUS "Detected Rust target: ${MINIJINJA_RUST_TARGET}")
message(STATUS "System libraries: ${MINIJINJA_SYSTEM_LIBS}")
