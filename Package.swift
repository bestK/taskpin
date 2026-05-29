// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskPin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TaskPin",
            dependencies: ["CLua", "TaskPinLua"],
            path: "src/macos",
            exclude: []
        ),
        .target(
            name: "TaskPinLua",
            dependencies: ["CLua"],
            path: "src/clua_bridge",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../lib/lua/include"),
                .headerSearchPath("../../lib/lua")
            ]
        ),
        .target(
            name: "CLua",
            path: "lib/lua",
            exclude: ["ljumptab.h", "lopnames.h"],
            publicHeadersPath: "include",
            cSettings: [
                .define("LUA_COMPAT_5_3"),
                .define("LUA_USE_MACOSX"),
                .headerSearchPath(".")
            ]
        ),
    ]
)
