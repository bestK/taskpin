#
# taskpin_bar.podspec — compiles native/mac/*.swift into the macOS runner.
#
# WHY A POD RATHER THAN A PBXPROJ EDIT
#
# The three Swift files under native/mac/ have to end up in the Runner target's
# Sources build phase. The two ways to get them there:
#
#   1. Hand-edit macos/Runner.xcodeproj/project.pbxproj: add three
#      PBXFileReference entries, three PBXBuildFile entries, add them to the
#      Runner group's children and to the Runner target's PBXSourcesBuildPhase,
#      and invent four unused 24-hex-digit object IDs that must not collide with
#      any of the ~700 lines already in that file. A mistake there does not fail
#      a build with a message — it produces a project Xcode refuses to open, or
#      silently drops a file from the compile, or corrupts the object graph for
#      the OTHER targets. It is also invisible in review: a pbxproj diff is
#      unreadable, so nobody will catch the mistake until a mac build is run.
#
#   2. This podspec + two lines in macos/Podfile. `flutter build macos` already
#      runs `pod install` (Flutter's macOS runner is CocoaPods-based and the
#      Podfile is the standard flutter create template), so the wiring is
#      regenerated from a human-readable file every build, by CocoaPods, which
#      is the tool that owns that job.
#
# (2) is chosen. The runner still needs one hand-written line to REGISTER the
# plugin — CocoaPods does not know about Flutter plugins, and
# macos/Flutter/GeneratedPluginRegistrant.swift is generated and must not be
# hand-edited. See MainFlutterWindow.swift.
#
# The source glob deliberately picks up every .swift in this directory, so a new
# native/mac file is wired in by existing rather than by editing anything:
#   DialogWindowStyles.swift  taskpin/window  (Phase 6)
#   StatusItemView.swift      the menu-bar bar renderer (Phase 8)
#   StatusItemPlugin.swift    taskpin/bar     (Phase 8)
#   PopoverHost.swift         the Flutter popover (Phase 8)
#
Pod::Spec.new do |s|
  s.name             = 'taskpin_bar'
  s.version          = '0.0.1'
  s.summary          = 'TaskPin native macOS menu-bar bar (NSStatusItem + Core Text).'
  s.description      = <<-DESC
The native macOS half of TaskPin: a custom NSView that renders the full span
list into an NSStatusItem with Core Text, the `taskpin/bar` MethodChannel, and
the Flutter-hosted NSPopover behind a click.
                       DESC
  s.homepage         = 'https://github.com/bestK/taskpin'
  s.license          = { :type => 'MIT' }
  s.author           = { 'bestK' => 'bestK' }
  s.source           = { :path => '.' }

  # Every Swift file in native/mac/. Relative to this podspec, which lives in
  # that directory (the Podfile points at it with `:path`).
  s.source_files     = '*.swift'

  # Must match `platform :osx` in macos/Podfile.
  s.platform         = :osx, '12.0'

  s.dependency 'FlutterMacOS'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
