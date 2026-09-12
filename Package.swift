// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaxInterviewCopilot",
    platforms: [.macOS("15.0")],
    products: [.library(name: "CopilotCore", targets: ["CopilotCore"]),
               .executable(name: "MaxInterviewCopilot", targets: ["MaxInterviewCopilot"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")],
    targets: [
        .target(name: "CopilotCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], path: "Core", exclude: ["DesignSystem"]),
        .executableTarget(name: "MaxInterviewCopilot", dependencies: ["CopilotCore"],
                          path: ".", exclude: ["Tests", "docs", "scripts", "Resources", "MaxInterviewCopilot.xcodeproj", "Core/Domain", "Core/Infrastructure", "README.md", "AGENTS.md", "STATUS.md", "DECISIONS.md", "CHANGELOG.md", "LICENSE-or-PERSONAL-USE-NOTICE.md", "Makefile", "build"],
                          sources: ["App", "Features", "Core/DesignSystem"]),
        .testTarget(name: "CopilotCoreTests", dependencies: ["CopilotCore"], path: "Tests/Unit")
    ],
    swiftLanguageModes: [.v6]
)
