# Feature Status

This matrix describes the implementation present in the repository. “Verified” means supported by inspected production code and automated coverage or a successful runtime check; it does not replace physical-device validation where hardware is required.

| Capability | Status | Notes |
|---|---|---|
| RoomPlan LiDAR capture | Implemented, hardware verification pending | Capture controller, readiness checks, permission flow, processing, and save pipeline are present. Real capture requires a supported device. |
| Original scan artifacts | Implemented and verified | CapturedRoom JSON, floor-plan JSON, and USDZ are stored separately with integrity metadata. |
| Project and scan persistence | Implemented and verified | SwiftData plus local file repositories and versioned migration are used. |
| Parametric 2D floor plan | Implemented and verified | Shared vertices, walls, rooms, openings, columns, beams, dimensions, and custom Canvas rendering are present. |
| Wall measurement correction | Implemented and verified | Local edits, constraint validation, protected measurements, preview, persistence, undo, and redo are implemented. |
| Door and window modeling | Implemented and verified | Host-relative geometry, horizontal and vertical measurements, provenance, conflicts, editing, and persistence are present. |
| Column and beam creation/editing | Implemented and verified | Creation, placement, dragging, hit testing, property sheets, geometry validation, and persistence are present. |
| 3D visualization | Implemented with limitation | RealityKit displays the original RoomPlan USDZ. Edited parametric geometry does not yet regenerate the 3D model. |
| PDF reports | Implemented and verified | Native PDF generation, persistence, preview, and sharing are present. |
| PhotoScan media drafts | Implemented, not fully runtime-verified | Camera/gallery capture, preprocessing, local drafts, and browsing exist. Photo-based reconstruction does not. |
| Photo-to-3D reconstruction | Planned | No reconstruction engine or Core ML model is integrated. |
| Core ML inference | Not present | No model file, Core ML import, or inference pipeline was found. |
| Bluetooth laser meter | Planned | No CoreBluetooth integration is present. |
| CAD/BIM export | Planned | DWG, DXF, IFC, OBJ, and FBX export are not implemented. |
| Edited USDZ generation | Planned | Original USDZ remains immutable; edited 3D export is not present. |
| Cloud synchronization | Not present | Current persistence is local. |

## Product Boundaries

iHomeScan is a measurement and geometry application, not a structural engineering verification tool. Column and beam geometry does not establish load-bearing capacity or code compliance. Numerical solver tolerances are also distinct from the physical uncertainty of a measurement device.
