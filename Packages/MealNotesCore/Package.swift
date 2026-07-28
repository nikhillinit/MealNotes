// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MealNotesCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "MealNotesCore", targets: ["MealNotesCore"])
    ],
    targets: [
        .target(
            name: "MealNotesCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MealNotesCoreTests",
            dependencies: ["MealNotesCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
