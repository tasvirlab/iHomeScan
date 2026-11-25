# Architecture

## System Overview

iHomeScan separates immutable scan evidence from editable precision geometry. This prevents a manual correction from overwriting the original RoomPlan capture and gives the editor a stable document to validate, persist, and reopen.

## Capture Pipeline

`ScannerReadinessView` checks device capability before entering the existing RoomPlan flow. Camera authorization is requested only from the user-initiated LiDAR workflow. `RoomPlanCaptureController` coordinates capture; the processing layer converts the resulting `CapturedRoom` into source JSON, floor-plan JSON, and USDZ artifacts. Persistence records checksums and stores files under the application's local support directory.

The simulator cannot perform RoomPlan capture. Its role is limited to non-capture flows and deterministic content.

## Persistence

SwiftData stores projects, floors, rooms, scans, assets, and reports through versioned schemas and a migration plan. Large artifacts remain files rather than opaque database blobs. Repository types provide the application-facing persistence boundary, and save paths use staged/atomic replacement where implemented.

Original RoomPlan assets are treated as immutable. `PrecisionPlanDocument` is the authoritative edited representation and retains revision and measurement metadata.

## Parametric Geometry

`ParametricFloorPlan` contains vertices, walls, rooms, hosted openings, columns, and beams in canonical meter units using `Double`. Walls refer to shared vertex identifiers, so connected geometry follows explicit topology without forcing irregular rooms into rectangles.

Openings use host-wall-relative coordinates. Columns support rectangular, square, and circular footprints. Beams represent overhead rectangular sections with horizontal endpoints and optional vertical relationships.

## Measurement and Validation

Measurement records distinguish estimated, manually entered, user-declared laser-verified, and derived values. Dedicated resolvers handle wall edits, opening measurement chains, and structural references. Validators reject nonfinite or impossible geometry, identify conflicts, and preserve the last committed document when a candidate fails.

The editing policy is intentionally local: a selected wall or element is revised without silently resizing unrelated geometry. Verified constraints are protected rather than weakened to manufacture a solution.

## 2D Rendering and Interaction

`FloorPlanCanvas` renders the authoritative parametric plan with SwiftUI `Canvas`. Presentation transforms account for fit, zoom, pan, and rotation while keeping model coordinates separate. Interaction includes element-priority hit testing, dimension labels, inline measurement sheets, previews, undo/redo, and structural placement/dragging.

Room area is derived from valid edited boundaries according to the precision area policy. Structural footprints are not automatically subtracted.

## 3D Visualization

The 3D viewer loads the original RoomPlan USDZ with RealityKit, with Quick Look support where appropriate. It is a source-scan viewer, not a regenerated representation of current precision edits. Synchronizing edited 2D geometry into a new 3D scene is future work.

## Reports

The report layer uses UIKit PDF rendering and PDFKit to generate, preview, persist, and share measurement reports. Reports consume available edited plan information without modifying source scan assets.

## PhotoScan Drafts

PhotoScan currently captures or imports photos and a bounded video, performs local media preparation, and stores drafts in an application-owned archive. This pipeline deliberately stops before reconstruction: no photogrammetry service, Core ML model, or 3D inference is present.

## Security and Privacy Notes

- Capture artifacts and photo drafts remain local.
- User-specific Xcode state, signing material, local captures, secrets, and the separate reconstruction laboratory are ignored by Git.
- The repository contains no cloud synchronization or analytics pipeline.
- Signing identifiers are build metadata, not embedded signing credentials.

## Known Architectural Limitations

- RoomPlan capture requires supported physical hardware.
- Edited geometry does not regenerate the USDZ model.
- Measurement provenance is user-declared; there is no authenticated Bluetooth instrument source.
- CAD/BIM exchange and photo reconstruction are not implemented.
- Geometry validation does not assert structural safety.
