// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Simplify",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SimplifyCore", targets: ["SimplifyCore"]),
        .executable(name: "simplify-probe", targets: ["SimplifyProbe"]),
        .executable(name: "Simplify", targets: ["SimplifyApp"]),
    ],
    targets: [
        .systemLibrary(name: "CZlib"),
        .systemLibrary(name: "CSQLite"),
        .target(name: "CFastLZ", publicHeadersPath: "include"),
        .target(name: "SimplifyCore", dependencies: ["CZlib", "CSQLite", "CFastLZ"], resources: [.process("Resources")]),
        .target(name: "SimplifyCatalog", dependencies: ["SimplifyCore"]),
        .executableTarget(name: "SimplifyApp", dependencies: ["SimplifyCatalog", "SimplifyCore", "CSQLite"]),
        .executableTarget(name: "SimplifyProbe", dependencies: ["SimplifyCore"]),
        .testTarget(name: "SimplifyCoreTests", dependencies: ["SimplifyCore", "CFastLZ"]),
        .testTarget(name: "SimplifyCatalogTests", dependencies: ["SimplifyCatalog", "SimplifyCore"]),
    ]
)
