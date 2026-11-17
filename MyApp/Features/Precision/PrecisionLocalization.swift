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
    static let unsavedTitle = LocalizedStringResource("precision.editor.unsaved.title", defaultValue: "Unsaved changes", comment: "Title before leaving the precision editor with unsaved edits")
    static let unsavedBody = LocalizedStringResource("precision.editor.unsaved.body", defaultValue: "Save your accepted floor plan changes before closing?", comment: "Message before leaving the precision editor")
    static let unsavedSave = LocalizedStringResource("precision.editor.unsaved.save", defaultValue: "Save and Close", comment: "Saves precision edits and closes the editor")
    static let unsavedDiscard = LocalizedStringResource("precision.editor.unsaved.discard", defaultValue: "Discard Changes", comment: "Discards unsaved precision edits")
    static let unsavedStatus = LocalizedStringResource("precision.editor.unsaved.status", defaultValue: "Unsaved", comment: "Compact status for accepted edits not yet written to disk")
    static let deselect = LocalizedStringResource("precision.editor.deselect", defaultValue: "Clear wall selection", comment: "Accessibility label for deselecting a wall")
    static let invalidMeasurement = LocalizedStringResource("precision.editor.invalidMeasurement", defaultValue: "Enter a positive measurement using the displayed unit.", comment: "Validation message for invalid wall length input")
    static let inlineTitle = LocalizedStringResource("precision.inline.title", defaultValue: "Wall length", comment: "Title of the inline wall measurement sheet")
    static let inlineCurrent = LocalizedStringResource("precision.inline.current", defaultValue: "Current: %@ mm", comment: "Current editable wall length in millimeters")
    static let inlineLidarCurrent = LocalizedStringResource("precision.inline.lidarCurrent", defaultValue: "LiDAR: %@ mm", comment: "Original LiDAR-estimated wall length in millimeters")
    static let inlineLaserCurrent = LocalizedStringResource("precision.inline.laserCurrent", defaultValue: "Laser verified: %@ mm", comment: "Current user-declared laser-verified wall length")
    static let inlineInput = LocalizedStringResource("precision.inline.input", defaultValue: "Measurement", comment: "Placeholder for millimeter wall length input")
    static let inlineLaser = LocalizedStringResource("precision.inline.laser", defaultValue: "Measured with a laser meter", comment: "User-declared laser measurement toggle")
    static let inlineAnchorQuestion = LocalizedStringResource("precision.inline.anchorQuestion", defaultValue: "Which corner should stay in place?", comment: "Shown only when wall length anchoring is ambiguous")
    static let inlineAnchorStart = LocalizedStringResource("precision.inline.anchorStart", defaultValue: "Start corner", comment: "Keep the wall start endpoint fixed")
    static let inlineAnchorEnd = LocalizedStringResource("precision.inline.anchorEnd", defaultValue: "End corner", comment: "Keep the wall end endpoint fixed")
    static let inlineConflict = LocalizedStringResource("precision.inline.conflict", defaultValue: "This measurement conflicts with protected geometry.", comment: "Simple hard-constraint conflict message")
    static let inlineConfirm = LocalizedStringResource("precision.inline.confirm", defaultValue: "Confirm measurement", comment: "Applies and automatically saves a wall measurement")
    static let inlineSaving = LocalizedStringResource("precision.inline.saving", defaultValue: "Saving…", comment: "Wall measurement save progress")
    static let inlineSaved = LocalizedStringResource("precision.inline.saved", defaultValue: "Saved", comment: "Brief confirmation after a durable precision save")
    static let inlineUnavailableTitle = LocalizedStringResource("precision.inline.unavailable.title", defaultValue: "Measurement editing unavailable", comment: "Title when editable parametric geometry cannot be loaded")
    static let inlineUnavailableBody = LocalizedStringResource("precision.inline.unavailable.body", defaultValue: "The scan is still safe, but its editable wall model could not be prepared. Try again.", comment: "Explains safe recovery when precision geometry loading fails")

    static func englishFallback(for key: String) -> String? {
        let values = [
            "precision.edit.title": "Edit Floor Plan", "precision.editor.title": "Precision Geometry",
            "precision.editor.undo": "Undo", "precision.editor.redo": "Redo",
            "precision.editor.original3D": "3D remains original scan", "precision.editor.selectWall": "Select a wall to inspect its measurements.",
            "precision.editor.wallDetails": "Wall details", "precision.anchor.start": "Keep start",
            "precision.anchor.end": "Keep end", "precision.source.manual": "Manual",
            "precision.source.laserVerified": "Laser verified", "precision.inline.title": "Wall length",
            "precision.inline.input": "Measurement", "precision.inline.laser": "Measured with a laser meter",
            "precision.inline.anchorQuestion": "Which corner should stay in place?", "precision.inline.anchorStart": "Start corner",
            "precision.inline.anchorEnd": "End corner", "precision.inline.conflict": "This measurement conflicts with protected geometry.",
            "precision.inline.confirm": "Confirm measurement", "precision.inline.saving": "Saving…",
            "precision.inline.saved": "Saved", "precision.inline.current": "Current: %@ mm",
            "precision.inline.lidarCurrent": "LiDAR: %@ mm", "precision.inline.laserCurrent": "Laser verified: %@ mm",
            "precision.inline.unavailable.title": "Measurement editing unavailable",
            "precision.inline.unavailable.body": "The scan is still safe, but its editable wall model could not be prepared. Try again."
        ]
        return values[key]
    }
}
