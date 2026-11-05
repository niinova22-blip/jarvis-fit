// swift-tools-version:5.9
// JarvisCore: platform-independent logic of JARVIS FIT (pose analysis, rep counting, workout
// session engine, voice intents, planner, nutrition, fit check math, adaptive engine).
// Depends only on Foundation so it builds and tests on macOS, Linux and Windows.
import PackageDescription

let package = Package(
    name: "JarvisCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JarvisCore", targets: ["JarvisCore"])
    ],
    targets: [
        .target(name: "JarvisCore"),
        .testTarget(name: "JarvisCoreTests", dependencies: ["JarvisCore"])
    ]
)
