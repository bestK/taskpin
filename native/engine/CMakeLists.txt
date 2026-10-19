# native/engine/CMakeLists.txt
#
# The unified, platform-neutral TaskPin Lua engine.
#
# Builds a STATIC library so the host can link it into a single binary with
# no runtime dependency (docs/FLUTTER_REWRITE_PLAN.md, "C 库的构建方式").
# The Flutter Windows runner will add_subdirectory() this from
# windows/CMakeLists.txt; macOS will reach it through a CocoaPods podspec.
#
# Lua is vendored from ../../lib/lua — the same copy the Windows build uses.
# Do NOT add a second Lua tree.

cmake_minimum_required(VERSION 3.16)
project(taskpin_engine C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Repo root, relative to this file (native/engine -> ../..).
get_filename_component(TP_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

set(TP_LUA_DIR "${TP_REPO_ROOT}/lib/lua")

if(NOT EXISTS "${TP_LUA_DIR}/lua.h")
    message(FATAL_ERROR "Vendored Lua not found at ${TP_LUA_DIR} (expected lua.h).")
endif()

# ─── Lua (vendored, compiled as part of this static lib) ───
#
# The prebuilt .o files in lib/lua are ignored; we compile the sources so the
# engine is toolchain-independent. LUA_COMPAT_5_3 must stay defined — the
# plan requires it and example scripts may rely on it.

file(GLOB TP_LUA_SOURCES CONFIGURE_DEPENDS "${TP_LUA_DIR}/*.c")
list(LENGTH TP_LUA_SOURCES TP_LUA_COUNT)
if(TP_LUA_COUNT EQUAL 0)
    message(FATAL_ERROR "No Lua sources found in ${TP_LUA_DIR}")
endif()

add_library(taskpin_lua STATIC ${TP_LUA_SOURCES})
target_include_directories(taskpin_lua PUBLIC "${TP_LUA_DIR}")
target_compile_definitions(taskpin_lua PRIVATE LUA_COMPAT_5_3)

if(WIN32)
    # Keep the Win32 surface minimal for the Lua core; it needs no more.
    target_compile_definitions(taskpin_lua PRIVATE WIN32_LEAN_AND_MEAN)
elseif(APPLE)
    target_compile_definitions(taskpin_lua PRIVATE LUA_USE_MACOSX)
else()
    target_compile_definitions(taskpin_lua PRIVATE LUA_USE_LINUX)
endif()

# Lua is third-party C; do not let its warnings fail our build.
if(MSVC)
    target_compile_options(taskpin_lua PRIVATE /w)
else()
    target_compile_options(taskpin_lua PRIVATE -w)
endif()

# ─── platform translation units ───

set(TP_ENGINE_SOURCES
    taskpin_lua.c
    tp_engine.c
    tp_json.c
)

set(TP_PLATFORM_SOURCES "")

if(WIN32)
    list(APPEND TP_PLATFORM_SOURCES
        tp_http_win.c
        tp_sysinfo_win.c
    )
elseif(APPLE)
    # Objective-C: NSURLSession / mach / sysctl. Currently #error stubs —
    # see tp_http_mac.m and tp_sysinfo_mac.m for status.
    enable_language(OBJC)
    list(APPEND TP_PLATFORM_SOURCES
        tp_http_mac.m
        tp_sysinfo_mac.m
    )
else()
    message(FATAL_ERROR "taskpin_engine has no platform implementation for this OS yet "
                        "(only Windows and macOS are planned).")
endif()

add_library(taskpin_engine STATIC
    ${TP_ENGINE_SOURCES}
    ${TP_PLATFORM_SOURCES}
)

target_include_directories(taskpin_engine
    PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}"
    PRIVATE "${TP_LUA_DIR}"
)

# PUBLIC so the header can include lua.h for consumers that need it; the ABI
# header itself stays Lua-free.
target_link_libraries(taskpin_engine PUBLIC taskpin_lua)

# The engine does NOT define UNICODE: the ABI is UTF-8 throughout.
if(WIN32)
    target_compile_definitions(taskpin_engine PRIVATE WIN32_LEAN_AND_MEAN)
    # user32 for GetAsyncKeyState (sys.key_pressed / sys.key_triggered) and
    # the locale calls are in kernel32, which is always linked. Listed
    # explicitly rather than relying on the toolchain's default libs.
    target_link_libraries(taskpin_engine PRIVATE winhttp iphlpapi psapi user32)
endif()

if(MSVC)
    # /utf-8 tells MSVC the source is UTF-8 (both the encoding it is read in and
    # the execution charset). Without it MSVC assumes the local ANSI codepage —
    # on a zh-CN box that is 936 — and warns C4819 on every file that carries a
    # Chinese comment, which is most of them. Worse, a non-ASCII byte sequence
    # that happens to be invalid in 936 can silently corrupt the string literals
    # rather than merely warning. The engine's ABI is UTF-8 throughout, so this
    # is the correct setting regardless of the build machine's locale.
    target_compile_options(taskpin_engine PRIVATE /W3 /utf-8)
    # The engine deliberately uses the plain C string functions (strncpy/strcpy/
    # wcsncpy/...). They are the portable spelling shared with the MinGW and
    # Clang builds; the _s variants are MSVC-only, so switching would fork the
    # source per toolchain. MSVC's C4996 is a deprecation nag, not a defect
    # report, so silence it rather than diverge.
    target_compile_definitions(taskpin_engine PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
    target_compile_options(taskpin_engine PRIVATE -Wall -Wextra)
endif()

# ─── CLI harness ───
#
# tool/engine_cli.c: run a script, print the TPScriptResult as JSON.
# Also the acceptance harness from the plan (Phase 2 验收).

option(TP_BUILD_CLI "Build the engine_cli JSON dump harness" ON)

if(TP_BUILD_CLI)
    set(TP_CLI_SOURCE "${TP_REPO_ROOT}/tool/engine_cli.c")
    if(NOT EXISTS "${TP_CLI_SOURCE}")
        message(FATAL_ERROR "tool/engine_cli.c not found at ${TP_CLI_SOURCE}")
    endif()

    add_executable(engine_cli "${TP_CLI_SOURCE}")
    target_link_libraries(engine_cli PRIVATE taskpin_engine)
    if(MSVC)
        # Same UTF-8 source reasoning as taskpin_engine above.
        target_compile_options(engine_cli PRIVATE /W3 /utf-8)
        target_compile_definitions(engine_cli PRIVATE _CRT_SECURE_NO_WARNINGS)
    endif()
    set_target_properties(engine_cli PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
endif()

# ─── optional shared library (Dart FFI test harness) ───
#
# The SHIPPED app links the engine STATICALLY (docs/FLUTTER_REWRITE_PLAN.md,
# "C 库的构建方式"): no DynamicLibrary.open() of an external DLL, so the
# product stays a single artifact with no runtime dependency.
#
# This target exists for ONE reason: packages/taskpin_engine's tests need to
# DynamicLibrary.open() the same C code so they can run on a box where the
# Flutter SDK is not usable. It is additive — no existing target's behaviour
# changes, and it is OFF by default so a normal build is byte-for-byte what it
# was before.
#
# The sources carry no __declspec(dllexport) (taskpin_engine.h must stay
# portable across MinGW/MSVC/clang), so WINDOWS_EXPORT_ALL_SYMBOLS lets CMake
# synthesise the export table from the object files instead of forking the
# header per toolchain.

option(TP_BUILD_SHARED "Also build taskpin_engine.dll for the Dart FFI tests" OFF)

if(TP_BUILD_SHARED)
    add_library(taskpin_engine_shared SHARED
        ${TP_ENGINE_SOURCES}
        ${TP_PLATFORM_SOURCES}
    )

    target_include_directories(taskpin_engine_shared
        PUBLIC  "${CMAKE_CURRENT_SOURCE_DIR}"
        PRIVATE "${TP_LUA_DIR}"
    )

    # taskpin_lua is STATIC; its objects are pulled into the DLL here. Its
    # LUA_COMPAT_5_3 definition is PRIVATE and deliberately does not
    # propagate — Lua is already compiled inside taskpin_lua.
    target_link_libraries(taskpin_engine_shared PRIVATE taskpin_lua)

    if(WIN32)
        target_compile_definitions(taskpin_engine_shared PRIVATE WIN32_LEAN_AND_MEAN)
        target_link_libraries(taskpin_engine_shared PRIVATE winhttp iphlpapi psapi user32)
    endif()

    if(MSVC)
        # Same UTF-8 / C4996 reasoning as taskpin_engine above.
        target_compile_options(taskpin_engine_shared PRIVATE /W3 /utf-8)
        target_compile_definitions(taskpin_engine_shared PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_compile_options(taskpin_engine_shared PRIVATE -Wall -Wextra)
    endif()

    # The DLL must be named taskpin_engine.dll — that is what the Dart loader
    # looks for. Its IMPORT library would also be taskpin_engine.lib, which
    # collides with the STATIC target's output and makes ninja fail with
    # "multiple rules generate taskpin_engine.lib". Send the import library to
    # a subdirectory so the two never share a filename; nobody links against it
    # anyway (Dart uses GetProcAddress, not the import lib).
    set_target_properties(taskpin_engine_shared PROPERTIES
        OUTPUT_NAME taskpin_engine
        WINDOWS_EXPORT_ALL_SYMBOLS ON
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/shared"
    )
endif()
