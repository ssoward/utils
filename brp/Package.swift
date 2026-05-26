// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BrotherPaul",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BrotherPaul", targets: ["BrotherPaul"])
    ],
    targets: [
        .executableTarget(
            name: "BrotherPaul",
            path: "Sources/BrotherPaul"
        )
    ]
)
