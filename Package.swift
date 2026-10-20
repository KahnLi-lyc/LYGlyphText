// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LYGlyphText",
    platforms: [.iOS(.v16)],
    products: [.library(name: "LYGlyphText", targets: ["LYGlyphText"])],
    targets: [
        .target(name: "LYGlyphText"),
        .testTarget(name: "LYGlyphTextTests", dependencies: ["LYGlyphText"])
    ],
    swiftLanguageModes: [.v6]
)
