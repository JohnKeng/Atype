// swift-tools-version: 6.2
// AtypeCore: the platform-independent part of Atype for iPhone (and anything
// Swift): the deterministic Chinese layer, the personal dictionary, the
// prompt presets, the LLM call and the shared iCloud config. Mirrors the Mac
// app's Rust `atype` module; tests share the same cases.
import PackageDescription

let package = Package(
    name: "AtypeCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [.library(name: "AtypeCore", targets: ["AtypeCore"])],
    dependencies: [
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git", revision: "1d8105a0f7199c90af722bff62728050c858e777"),
    ],
    targets: [
        .target(
            name: "AtypeCore",
            dependencies: [.product(name: "OpenCC", package: "SwiftyOpenCC")],
            resources: [.copy("Resources/presets.json")]
        ),
        .testTarget(name: "AtypeCoreTests", dependencies: ["AtypeCore"]),
    ]
)
