// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FileDownloader", // This can remain the same; it’s the package name, not the module name.
    platforms: [
        .iOS("17.0"),
        .macOS("15.0")
    ],
    products: [
        .library(
            name: "FileDownloadManager", // 👈 This is the name you will import
            targets: ["FileDownloadManager"] // 👈 Matches the target below
        ),
    ],
    targets: [
        .target(
            name: "FileDownloadManager", // 👈 The target that compiles your code
        ),
    ]
)
