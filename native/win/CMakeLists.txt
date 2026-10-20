# ============================================================================
#  TaskPin native Windows bar (Phase 7 prototype) — MinGW-w64 build
# ============================================================================
#  Build (from the repo root):
#    cmake -S native/win -B native/win/build -G Ninja \
#          -DCMAKE_C_COMPILER=D:/mingw64/bin/gcc.exe \
#          -DCMAKE_CXX_COMPILER=D:/mingw64/bin/g++.exe
#    ninja -C native/win/build
#
#  Targets:
#    taskpin_bar_demo.exe   standalone harness (live demo + --selftest)
#    taskpin_bar            static library for the later Flutter plugin
# ============================================================================
cmake_minimum_required(VERSION 3.20)
project(taskpin_bar CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Repo root so bar_image.cpp can include lib/stb_image.h read-only.
get_filename_component(TASKPIN_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

add_compile_definitions(
  UNICODE _UNICODE
  WIN32_LEAN_AND_MEAN
  _WIN32_WINNT=0x0602        # Win8+: layered child windows, D2D 1.1
  NOMINMAX
)

set(BAR_SOURCES
  bar_embed.cpp
  bar_image.cpp
  bar_render_d2d.cpp
  bar_window.cpp
  bar_channel.cpp
  # The `taskpin/window` channel for script dialogs. It compiles down to
  # nothing without TASKPIN_FLUTTER_PLUGIN (set below), so the standalone
  # MinGW harness is unaffected; in the runner it is what gives a dialog its
  # frame, opacity, clickthrough and drag.
  #
  # This file was written in Phase 6 and then never added to any CMakeLists, so
  # `taskpin/window` did not exist in the shipped Windows build: every
  # `setFrame` / `setBorderless` / `setOpacity` call failed and dialogs opened
  # at the OS default 800x600 with a system title bar.
  dialog_window_styles.cpp
)

set(BAR_LIBS
  d2d1 dwrite windowscodecs d3d11 dxgi dwmapi
  ole32 uuid user32 gdi32 shell32 shlwapi winhttp
  comctl32
)

# ---- static library for the later Flutter plugin ----
add_library(taskpin_bar STATIC ${BAR_SOURCES})
target_include_directories(taskpin_bar PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${TASKPIN_ROOT}")
target_link_libraries(taskpin_bar PUBLIC ${BAR_LIBS})

# `bar_channel.cpp` is the `taskpin/bar` MethodChannel. It needs the Flutter
# headers, which only exist when this module is built as part of the Flutter
# runner — i.e. when the `flutter` interface target is defined by
# `windows/flutter/CMakeLists.txt`. A standalone MinGW build of this directory
# (the demo harness path) has no Flutter and compiles the file down to nothing,
# exactly as `dialog_window_styles.cpp` does with the same define.
#
# `flutter_wrapper_plugin` supplies `flutter::Plugin`, which the channel's plugin
# object derives from so the registrar owns its lifetime.
if(TARGET flutter AND TARGET flutter_wrapper_plugin)
  target_compile_definitions(taskpin_bar PRIVATE TASKPIN_FLUTTER_PLUGIN)
  target_link_libraries(taskpin_bar PUBLIC flutter_wrapper_plugin)
  target_include_directories(taskpin_bar PUBLIC
    "${TASKPIN_ROOT}/windows/flutter/ephemeral/cpp_client_wrapper/include")
endif()

# Warning flags are per-toolchain: MSVC rejects `-Wall`/`-Wextra` outright
# (D8021: invalid numeric argument), so the GCC spelling cannot be used
# unconditionally. The library is linked into the Flutter Windows runner, which
# is built with MSVC, so this branch is the one that actually ships.
if(MSVC)
  # /W4 is MSVC's "reasonable" level; /WX- keeps warnings from failing the
  # build, matching the non-fatal -Wall -Wextra behaviour below.
  target_compile_options(taskpin_bar PRIVATE /W4 /WX-)
  target_compile_definitions(taskpin_bar PRIVATE _CRT_SECURE_NO_WARNINGS)
else()
  target_compile_options(taskpin_bar PRIVATE -Wall -Wextra)
endif()

# ---- standalone demo harness ----
add_executable(taskpin_bar_demo bar_demo.cpp)
target_include_directories(taskpin_bar_demo PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${TASKPIN_ROOT}")
target_link_libraries(taskpin_bar_demo PRIVATE taskpin_bar ${BAR_LIBS})

# Console subsystem: we want the log output on stdout for evidence.
# -municode gives us wmain() — a MinGW spelling. MSVC selects the console
# subsystem through its own flags and rejects -municode, so gate it. The demo
# is excluded from the Flutter build entirely (see windows/CMakeLists.txt), so
# this only affects a direct MinGW build of the harness.
if(MINGW)
  target_compile_options(taskpin_bar_demo PRIVATE -municode)
  target_link_options(taskpin_bar_demo PRIVATE -municode)

  # Statically link libstdc++/libgcc so the exe runs without the MinGW DLLs.
  target_link_options(taskpin_bar_demo PRIVATE -static -static-libgcc -static-libstdc++)
endif()
