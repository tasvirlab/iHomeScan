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
    static let openingDoorTitle = LocalizedStringResource("precision.opening.doorTitle", defaultValue: "Door %@", comment: "Title of the selected door measurement sheet; placeholder is its ordinal number")
    static let openingWindowTitle = LocalizedStringResource("precision.opening.windowTitle", defaultValue: "Window %@", comment: "Title of the selected window measurement sheet; placeholder is its ordinal number")
    static let openingGenericTitle = LocalizedStringResource("precision.opening.genericTitle", defaultValue: "Opening %@", comment: "Title of the selected generic wall opening measurement sheet; placeholder is its ordinal number")
    static let openingOther = LocalizedStringResource("precision.opening.other", defaultValue: "Other measurements", comment: "Disclosure for optional opening measurements")
    static let openingWhichCorner = LocalizedStringResource("precision.opening.whichCorner", defaultValue: "Which corner did you measure from?", comment: "Asks the surveyor to choose a wall endpoint reference")
    static let openingWallStart = LocalizedStringResource("precision.opening.wallStart", defaultValue: "Corner A", comment: "First visually marked endpoint of the host wall")
    static let openingWallEnd = LocalizedStringResource("precision.opening.wallEnd", defaultValue: "Corner B", comment: "Second visually marked endpoint of the host wall")
    static let openingDoorOffset = LocalizedStringResource("precision.opening.doorOffset", defaultValue: "Corner to door", comment: "Distance from selected corner to the near door edge")
    static let openingWindowOffset = LocalizedStringResource("precision.opening.windowOffset", defaultValue: "Corner to window", comment: "Distance from selected corner to the near window edge")
    static let openingDoorWidth = LocalizedStringResource("precision.opening.doorWidth", defaultValue: "Door width", comment: "Door opening width")
    static let openingWindowWidth = LocalizedStringResource("precision.opening.windowWidth", defaultValue: "Window width", comment: "Window opening width")
    static let openingDoorHeight = LocalizedStringResource("precision.opening.doorHeight", defaultValue: "Door height", comment: "Door opening height")
    static let openingWindowHeight = LocalizedStringResource("precision.opening.windowHeight", defaultValue: "Window height", comment: "Window opening height")
    static let openingSill = LocalizedStringResource("precision.opening.sill", defaultValue: "Floor to window sill", comment: "Window sill elevation above floor")
    static let openingThreshold = LocalizedStringResource("precision.opening.threshold", defaultValue: "Threshold elevation", comment: "Door threshold elevation")
    static let openingTop = LocalizedStringResource("precision.opening.top", defaultValue: "Top elevation", comment: "Opening top elevation")
    static let openingConfirm = LocalizedStringResource("precision.opening.confirm", defaultValue: "Confirm measurements", comment: "Validates and automatically saves opening measurements")
    static let openingInvalid = LocalizedStringResource("precision.opening.invalid", defaultValue: "Check the entered measurements.", comment: "Fallback opening validation error")
    static let openingOverlap = LocalizedStringResource("precision.opening.overlap", defaultValue: "This opening would overlap another opening.", comment: "Opening overlap validation error")
    static let openingProtectedConflict = LocalizedStringResource("precision.opening.protectedConflict", defaultValue: "This value conflicts with a verified measurement.", comment: "Protected opening measurement conflict")
    static let openingReferenceRequired = LocalizedStringResource("precision.opening.referenceRequired", defaultValue: "Choose corner A or B for this distance.", comment: "Explains why an edited corner offset needs a reference")
    static let openingNoChanges = LocalizedStringResource("precision.opening.noChanges", defaultValue: "Change a measurement to enable confirmation.", comment: "Explains a disabled opening confirmation button")
    static let openingUnknown = LocalizedStringResource("precision.opening.unknown", defaultValue: "Not measured", comment: "Value shown for an optional unknown opening measurement")
    static let openingStartOffset = LocalizedStringResource("precision.opening.startOffset", defaultValue: "From corner A", comment: "Read-only distance from corner A")
    static let openingEndOffset = LocalizedStringResource("precision.opening.endOffset", defaultValue: "From corner B", comment: "Read-only distance from corner B")
    static let structuralStrings: [LocalizedStringResource] = [
        .init("precision.structural.addTitle", defaultValue: "Add element", comment: "Title and accessibility label for adding a structural element"),
        .init("precision.structural.column", defaultValue: "Column", comment: "Architectural column option"),
        .init("precision.structural.beam", defaultValue: "Beam", comment: "Overhead beam option"),
        .init("precision.structural.columnHint", defaultValue: "Place a column footprint on the plan", comment: "Column creation explanation"),
        .init("precision.structural.beamHint", defaultValue: "Mark the beam start and end", comment: "Beam creation explanation"),
        .init("precision.structural.shape", defaultValue: "Shape", comment: "Column shape picker label"),
        .init("precision.structural.rectangular", defaultValue: "Rectangle", comment: "Rectangular column shape"),
        .init("precision.structural.square", defaultValue: "Square", comment: "Square column shape"),
        .init("precision.structural.circular", defaultValue: "Circle", comment: "Circular column shape"),
        .init("precision.structural.columnTitle", defaultValue: "Column dimensions", comment: "Column creation dimension sheet title"),
        .init("precision.structural.beamTitle", defaultValue: "Beam dimensions", comment: "Beam creation dimension sheet title"),
        .init("precision.structural.width", defaultValue: "Width", comment: "Structural element width"),
        .init("precision.structural.depth", defaultValue: "Depth", comment: "Structural element depth"),
        .init("precision.structural.side", defaultValue: "Side length", comment: "Square column side length"),
        .init("precision.structural.diameter", defaultValue: "Diameter", comment: "Circular column diameter"),
        .init("precision.structural.height", defaultValue: "Height", comment: "Column height"),
        .init("precision.structural.rotation", defaultValue: "Rotation", comment: "Column rotation in degrees"),
        .init("precision.structural.baseElevation", defaultValue: "Base elevation", comment: "Column base elevation"),
        .init("precision.structural.bottomElevation", defaultValue: "Bottom elevation", comment: "Beam bottom elevation above floor"),
        .init("precision.structural.topElevation", defaultValue: "Top elevation", comment: "Beam top elevation"),
        .init("precision.structural.optional", defaultValue: "Other dimensions", comment: "Optional structural measurements disclosure"),
        .init("precision.structural.optionalShort", defaultValue: "optional", comment: "Marks an optional measurement"),
        .init("precision.structural.addColumn", defaultValue: "Add column", comment: "Confirms column creation"),
        .init("precision.structural.addBeam", defaultValue: "Add beam", comment: "Confirms beam creation"),
        .init("precision.structural.tapPlacement", defaultValue: "Tap the placement point on the plan", comment: "Instruction during structural placement"),
        .init("precision.structural.tapColumnPlacement", defaultValue: "Tap where the column should be placed", comment: "Column placement instruction"),
        .init("precision.structural.tapBeamStart", defaultValue: "Tap the beam start point", comment: "Beam start placement instruction"),
        .init("precision.structural.tapBeamEnd", defaultValue: "Tap the beam end point", comment: "Beam end placement instruction"),
        .init("precision.structural.placeRequired", defaultValue: "Choose a placement on the plan", comment: "Missing placement error"),
        .init("precision.structural.invalidDimension", defaultValue: "Enter valid positive dimensions", comment: "Invalid structural dimension error"),
        .init("precision.structural.saveFailed", defaultValue: "The change was not saved. Try again.", comment: "Structural creation save failure"),
        .init("precision.structural.columnProperties", defaultValue: "Column measurements", comment: "Column properties sheet title"),
        .init("precision.structural.beamProperties", defaultValue: "Beam measurements", comment: "Beam properties sheet title"),
        .init("precision.structural.confirmChanges", defaultValue: "Confirm measurements", comment: "Confirms structural property changes"),
        .init("precision.structural.laserMeasured", defaultValue: "Measured with a laser meter", comment: "User-declared structural measurement provenance"),
        .init("precision.structural.position", defaultValue: "Position", comment: "Structural position disclosure"),
        .init("precision.structural.positionX", defaultValue: "Position X", comment: "Column X coordinate"),
        .init("precision.structural.positionY", defaultValue: "Position Y", comment: "Column Y coordinate"),
        .init("precision.structural.startPoint", defaultValue: "Start point", comment: "Beam start point"),
        .init("precision.structural.endPoint", defaultValue: "End point", comment: "Beam end point"),
        .init("precision.structural.axisX", defaultValue: "X", comment: "Horizontal coordinate axis"),
        .init("precision.structural.axisY", defaultValue: "Y", comment: "Vertical coordinate axis"),
        .init("precision.structural.verticalMeasurements", defaultValue: "Height and elevation", comment: "Structural vertical measurements disclosure"),
        .init("precision.structural.noChanges", defaultValue: "Change a measurement to enable confirmation.", comment: "No structural property changes"),
        .init("precision.structural.verticalConflict", defaultValue: "The elevation and depth measurements do not agree.", comment: "Beam vertical measurement conflict")
    ]

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
            , "precision.opening.doorTitle": "Door %@", "precision.opening.windowTitle": "Window %@",
            "precision.opening.genericTitle": "Opening %@", "precision.opening.other": "Other measurements",
            "precision.opening.whichCorner": "Which corner did you measure from?", "precision.opening.wallStart": "Corner A",
            "precision.opening.wallEnd": "Corner B", "precision.opening.doorOffset": "Corner to door",
            "precision.opening.windowOffset": "Corner to window", "precision.opening.doorWidth": "Door width",
            "precision.opening.windowWidth": "Window width", "precision.opening.doorHeight": "Door height",
            "precision.opening.windowHeight": "Window height", "precision.opening.sill": "Floor to window sill",
            "precision.opening.threshold": "Threshold elevation", "precision.opening.top": "Top elevation",
            "precision.opening.confirm": "Confirm measurements", "precision.opening.invalid": "Check the entered measurements.",
            "precision.opening.overlap": "This opening would overlap another opening.",
            "precision.opening.protectedConflict": "This value conflicts with a verified measurement.",
            "precision.opening.referenceRequired": "Choose corner A or B for this distance.",
            "precision.opening.noChanges": "Change a measurement to enable confirmation.",
            "precision.opening.unknown": "Not measured", "precision.opening.startOffset": "From corner A",
            "precision.opening.endOffset": "From corner B",
            "precision.structural.addTitle": "Add element", "precision.structural.column": "Column",
            "precision.structural.beam": "Beam", "precision.structural.columnHint": "Place a column footprint on the plan",
            "precision.structural.beamHint": "Mark the beam start and end", "precision.structural.shape": "Shape",
            "precision.structural.rectangular": "Rectangle", "precision.structural.square": "Square",
            "precision.structural.circular": "Circle", "precision.structural.columnTitle": "Column dimensions",
            "precision.structural.beamTitle": "Beam dimensions", "precision.structural.width": "Width",
            "precision.structural.depth": "Depth", "precision.structural.side": "Side length",
            "precision.structural.diameter": "Diameter", "precision.structural.height": "Height",
            "precision.structural.rotation": "Rotation", "precision.structural.baseElevation": "Base elevation",
            "precision.structural.bottomElevation": "Bottom elevation", "precision.structural.topElevation": "Top elevation",
            "precision.structural.optional": "Other dimensions", "precision.structural.optionalShort": "optional",
            "precision.structural.addColumn": "Add column", "precision.structural.addBeam": "Add beam",
            "precision.structural.tapPlacement": "Tap the placement point on the plan",
            "precision.structural.tapColumnPlacement": "Tap where the column should be placed",
            "precision.structural.tapBeamStart": "Tap the beam start point",
            "precision.structural.tapBeamEnd": "Tap the beam end point",
            "precision.structural.placeRequired": "Choose a placement on the plan",
            "precision.structural.invalidDimension": "Enter valid positive dimensions",
            "precision.structural.saveFailed": "The change was not saved. Try again.",
            "precision.structural.columnProperties": "Column measurements",
            "precision.structural.beamProperties": "Beam measurements",
            "precision.structural.confirmChanges": "Confirm measurements",
            "precision.structural.laserMeasured": "Measured with a laser meter",
            "precision.structural.position": "Position",
            "precision.structural.positionX": "Position X",
            "precision.structural.positionY": "Position Y",
            "precision.structural.startPoint": "Start point",
            "precision.structural.endPoint": "End point",
            "precision.structural.axisX": "X", "precision.structural.axisY": "Y",
            "precision.structural.verticalMeasurements": "Height and elevation",
            "precision.structural.noChanges": "Change a measurement to enable confirmation.",
            "precision.structural.verticalConflict": "The elevation and depth measurements do not agree."
        ]
        return values[key]
    }
}
