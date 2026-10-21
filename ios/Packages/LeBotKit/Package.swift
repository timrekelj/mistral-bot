// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LeBotKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LeBotCore", targets: ["LeBotCore"]),
        .library(name: "LeBotDesign", targets: ["LeBotDesign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "LeBotCore",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")]
        ),
        .target(name: "LeBotDesign"),
        .testTarget(name: "LeBotCoreTests", dependencies: ["LeBotCore"]),
    ]
)
