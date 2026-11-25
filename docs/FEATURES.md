# Feature Status

This table distinguishes code present in the repository from runtime and hardware validation. **Implemented** does not mean that the full automated suite or physical-device capture has passed.

| Capability | Current implementation | Verification boundary |
|---|---|---|
| RoomPlan capture | Capture controller, readiness checks, permissions, processing, and save flow | Requires LiDAR-capable hardware for end-to-end validation |
| Original capture artifacts | CapturedRoom JSON, floor-plan JSON, and USDZ saved separately with integrity metadata | Source artifacts are retained independently of edits |
| Local project persistence | SwiftData, versioned schemas, and local asset repositories | Build verified during publication; full test-suite completion was not confirmed |
| Parametric 2D editor | Shared vertices, walls, openings, columns, beams, and Canvas rendering | Dense-plan annotation collisions remain a known UI issue |
| Wall revisions | Local length edits, previews, validation, protected constraints, undo/redo | Behavior is covered by source and tests; full suite execution was interrupted |
| Doors and windows | Host-relative placement, dimensions, editing, and measurement metadata | Manual editing; no Bluetooth instrument integration |
| Columns and beams | Creation, placement, dragging, property editing, and validation | Geometry modeling does not establish structural adequacy |
| 3D reference | RealityKit/Quick Look viewing of original RoomPlan USDZ | Edited geometry does not regenerate USDZ |
| PDF reports | Local report generation, preview, persistence, and sharing | PDF reporting is present; CAD/BIM export is not |
| PhotoScan drafts | Capture/import, local media preparation, and draft storage | Photo-to-3D reconstruction is not implemented |
| Localization | English, Uzbek, and Russian | Language coverage does not imply every workflow is visually reviewed |
| Core ML inference | Not integrated | No reconstruction model or inference pipeline |
| Bluetooth laser meters | Not integrated | Existing “laser-verified” provenance is user-declared, not device-authenticated |
| DXF, DWG, IFC, OBJ, FBX exports | Not implemented | Planned engineering work |
| Edited 3D generation | Not implemented | Original USDZ remains unchanged |
| Cloud sync | Not implemented | Current user data is stored locally |

## Validation at Publication

The reported publication audit confirmed an application build and build-for-testing, discovered **271 tests**, and verified English simulator screenshots. The full test run **did not complete** because CoreSimulatorService disconnected. No passing test count should be inferred from discovery or a successful build.

Physical-device RoomPlan capture was not verified in that publication pass. See [Development](DEVELOPMENT.md) for repeatable commands and hardware requirements.

## Scope and Accuracy

iHomeScan is a geometry and measurement application, not a structural safety assessment tool. Numerical geometry tolerances and user-declared verification states must not be treated as proof of physical measurement accuracy.
