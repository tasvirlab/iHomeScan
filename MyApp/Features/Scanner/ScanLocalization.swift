import Foundation

/// Compile-time String Catalog seeds for the dynamic in-app localization lookup.
enum ScanLocalization {
    static let resources: [LocalizedStringResource] = [
        .init("scan.choice.section", defaultValue: "Start scanning", comment: "Home section title above photo and LiDAR scan choices"),
        .init("scan.choice.title", defaultValue: "Choose scan type", comment: "Scan method choice sheet title"),
        .init("scan.choice.photo.title", defaultValue: "Photo Scan", comment: "Photo-based reconstruction method name"),
        .init("scan.choice.photo.summary", defaultValue: "Textured 3D model from photos or video.", comment: "Photo scan card summary"),
        .init("scan.choice.photo.requirement", defaultValue: "LiDAR is not required.", comment: "Photo scan hardware requirement"),
        .init("scan.choice.lidar.title", defaultValue: "Lidar Scan", comment: "LiDAR room scanning method name"),
        .init("scan.choice.lidar.summary", defaultValue: "Room plan and measurements.", comment: "LiDAR scan card summary"),
        .init("scan.choice.lidar.available", defaultValue: "Available on this device.", comment: "LiDAR scan available status"),
        .init("scan.choice.lidar.requirement", defaultValue: "A LiDAR-equipped device is required.", comment: "LiDAR scan unavailable reason"),
    ]
}
