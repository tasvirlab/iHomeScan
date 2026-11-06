import Foundation

/// Declares dynamic AppSettings keys so Xcode can extract their English source values.
enum PrecisionLocalization {
    static let editTitle = LocalizedStringResource(
        "precision.edit.title",
        defaultValue: "Edit Floor Plan",
        comment: "Button that opens the read-only parametric floor plan inspector"
    )
    static let editorTitle = LocalizedStringResource(
        "precision.editor.title",
        defaultValue: "Precision Geometry",
        comment: "Navigation title for the parametric geometry inspector"
    )
    static let errorTitle = LocalizedStringResource(
        "precision.editor.error.title",
        defaultValue: "Geometry unavailable",
        comment: "Title shown when parametric geometry cannot be loaded"
    )
    static let errorBody = LocalizedStringResource(
        "precision.editor.error.body",
        defaultValue: "The saved scan could not be converted into parametric geometry.",
        comment: "Explanation shown when parametric conversion fails"
    )
    static let incompleteTitle = LocalizedStringResource(
        "precision.editor.incomplete.title",
        defaultValue: "Incomplete geometry",
        comment: "Warning title for a partial RoomPlan scan"
    )
    static let incompleteBody = LocalizedStringResource(
        "precision.editor.incomplete.body",
        defaultValue: "Open wall chains are preserved. Missing boundaries are not fabricated.",
        comment: "Warning explaining honest handling of a partial scan"
    )
    static let selectWall = LocalizedStringResource(
        "precision.editor.selectWall",
        defaultValue: "Select a wall to inspect its measurements.",
        comment: "Instruction displayed below the parametric plan"
    )
    static let wallDetails = LocalizedStringResource(
        "precision.editor.wallDetails",
        defaultValue: "Wall details",
        comment: "Heading for selected wall metadata"
    )
    static let canvas = LocalizedStringResource(
        "precision.editor.canvas",
        defaultValue: "Selectable parametric floor plan",
        comment: "Accessibility label for the parametric plan canvas"
    )
    static let wallLength = LocalizedStringResource(
        "precision.wall.length",
        defaultValue: "Length",
        comment: "Derived wall length label"
    )
    static let wallHeight = LocalizedStringResource(
        "precision.wall.height",
        defaultValue: "Height",
        comment: "Wall height label"
    )
    static let wallThickness = LocalizedStringResource(
        "precision.wall.thickness",
        defaultValue: "Thickness",
        comment: "Wall thickness label"
    )
    static let lidarSource = LocalizedStringResource(
        "precision.source.lidar",
        defaultValue: "LiDAR estimate",
        comment: "Measurement provenance from RoomPlan and LiDAR"
    )
    static let estimatedVerification = LocalizedStringResource(
        "precision.verification.estimated",
        defaultValue: "Estimated · not verified",
        comment: "Verification state for an unverified LiDAR measurement"
    )
}
