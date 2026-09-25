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
        .target(name: "SimplifyCore", dependencies: ["CZlib", "CSQLite"]),
        .target(name: "SimplifyCatalog", dependencies: ["SimplifyCore"]),
        .executableTarget(name: "SimplifyApp", dependencies: ["SimplifyCatalog", "SimplifyCore"]),
        .executableTarget(name: "SimplifyProbe", dependencies: ["SimplifyCore"]),
        .testTarget(name: "SimplifyCoreTests", dependencies: ["SimplifyCore"]),
        .testTarget(name: "SimplifyCatalogTests", dependencies: ["SimplifyCatalog", "SimplifyCore"]),
    ]
)
