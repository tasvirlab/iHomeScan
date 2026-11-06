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
    static let dimension = LocalizedStringResource("precision.editor.dimension", defaultValue: "New length", comment: "Field for entering a revised wall length")
    static let anchor = LocalizedStringResource("precision.editor.anchor", defaultValue: "Fixed endpoint", comment: "Picker title for the endpoint that remains fixed")
    static let anchorStart = LocalizedStringResource("precision.anchor.start", defaultValue: "Keep start", comment: "Keeps the wall start endpoint fixed")
    static let anchorEnd = LocalizedStringResource("precision.anchor.end", defaultValue: "Keep end", comment: "Keeps the wall end endpoint fixed")
    static let measurementSource = LocalizedStringResource("precision.editor.source", defaultValue: "Measurement source", comment: "Picker title for measurement provenance")
    static let manualSource = LocalizedStringResource("precision.source.manual", defaultValue: "Manual", comment: "A manually entered, unverified measurement")
    static let laserSource = LocalizedStringResource("precision.source.laserVerified", defaultValue: "Laser verified", comment: "Explicitly marks a manually entered laser measurement as verified")
    static let conflict = LocalizedStringResource("precision.editor.conflict", defaultValue: "This change conflicts with protected geometry.", comment: "Constraint solver conflict warning")
    static let apply = LocalizedStringResource("precision.editor.apply", defaultValue: "Apply", comment: "Commits a valid geometry preview")
    static let undo = LocalizedStringResource("precision.editor.undo", defaultValue: "Undo", comment: "Reverts the last committed geometry revision")
    static let redo = LocalizedStringResource("precision.editor.redo", defaultValue: "Redo", comment: "Reapplies the last undone geometry revision")
    static let original3D = LocalizedStringResource("precision.editor.original3D", defaultValue: "3D remains original scan", comment: "Clarifies that USDZ does not reflect precision edits")
    static let saveErrorTitle = LocalizedStringResource("precision.editor.saveError.title", defaultValue: "Could not save changes", comment: "Precision geometry persistence error title")
    static let saveErrorBody = LocalizedStringResource("precision.editor.saveError.body", defaultValue: "The previous saved geometry is unchanged. Try again.", comment: "Precision geometry persistence recovery message")
}
