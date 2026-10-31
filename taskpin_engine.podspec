#
# taskpin_engine.podspec — compiles the unified Lua engine into the macOS app.
#
# WHY THIS LIVES AT THE REPO ROOT (rather than beside native/engine)
#
# CocoaPods only matches `source_files` against files it enumerated under the
# pod's root directory; a pattern that climbs out with `../../` is silently
# ignored. The engine needs both native/engine/* and the vendored lib/lua/*
# tree, so their common ancestor — the repo root — has to be the pod root.
# The Podfile therefore points here with `:path => '..'`.
#
# WHY A POD
#
# The engine is plain C/Objective-C plus a vendored Lua tree. Windows links it
# statically through windows/CMakeLists.txt; macOS has no CMake step in the
# Flutter build, so the same sources are compiled by CocoaPods into a framework
# embedded in Runner.app. `pod install` is already run by `flutter build macos`,
# so this podspec plus one Podfile line is the whole wiring — no hand-edited
# pbxproj (see native/mac/taskpin_bar.podspec for the same reasoning).
#
# WHY A DYNAMIC FRAMEWORK (the default with `use_frameworks!`)
#
# Every source file listed here is compiled straight into the framework's
# dylib. Object files passed to the linker are always kept, so the `tp_*`
# entry points are exported and discoverable at runtime with dlsym from
# `DynamicLibrary.process()` in packages/taskpin_engine. A static framework
# would instead be an archive whose members are only pulled in by link-time
# references — and Dart resolves these symbols at runtime, so nothing would
# reference them and the linker could drop every object.
#
# Only the macOS platform translation units are listed. tp_http_win.c and
# tp_sysinfo_win.c are Windows-only, and tool/engine_cli.c is a CLI harness,
# not part of the library.
#
Pod::Spec.new do |s|
  s.name             = 'taskpin_engine'
  s.version          = '0.0.1'
  s.summary          = 'TaskPin unified Lua script engine (macOS).'
  s.description      = <<-DESC
The platform-neutral TaskPin Lua engine (taskpin_lua.c, tp_engine.c, tp_json.c),
the macOS platform TUs (tp_http_mac.m, tp_sysinfo_mac.m) and the vendored Lua
sources, linked into one framework for the Flutter macOS runner.
                       DESC
  s.homepage         = 'https://github.com/bestK/taskpin'
  s.license          = { :type => 'MIT' }
  s.author           = { 'bestK' => 'bestK' }
  s.source           = { :path => '.' }

  # Explicit list rather than a glob: native/engine also holds the Windows TUs,
  # which must not be compiled here, and the repo has older C sources in src/
  # and lib/ that are not part of this engine.
  s.source_files     = [
    'native/engine/taskpin_lua.c',
    'native/engine/tp_engine.c',
    'native/engine/tp_json.c',
    'native/engine/tp_http_mac.m',
    'native/engine/tp_sysinfo_mac.m',
    'lib/lua/*.c',
  ]

  # Must match `platform :osx` in macos/Podfile.
  s.platform         = :osx, '12.0'

  s.requires_arc     = true

  # tp_engine.c/taskpin_lua.c include "lua.h" etc.; Lua itself is compiled from
  # lib/lua, so that directory is the include root. LUA_COMPAT_5_3 and
  # LUA_USE_MACOSX mirror native/engine/CMakeLists.txt.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/lib/lua',
    'GCC_PREPROCESSOR_DEFINITIONS' =>
      '$(inherited) LUA_COMPAT_5_3 LUA_USE_MACOSX',
  }

  # Foundation: NSURLSession / NSLocale.
  # IOKit:      IOPSCopyPowerSourcesInfo (sys.battery).
  # CoreGraphics: CGEventSourceKeyState / ButtonState (sys.key_*).
  s.frameworks       = 'Foundation', 'IOKit', 'CoreGraphics'
  # libproc: proc_listpids / proc_pidinfo / proc_pid_rusage.
  s.libraries        = 'proc'
end
