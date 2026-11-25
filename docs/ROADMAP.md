# Roadmap

This roadmap describes intended directions, not shipped capabilities. Priorities may change as measurement workflows are validated with architects and supported devices.

## Precision Measurement

- Connect selected commercial Bluetooth laser distance meters through a dedicated CoreBluetooth integration.
- Record authenticated device provenance separately from manual and user-declared laser measurements.
- Improve uncertainty, calibration, and conflict-resolution workflows without weakening verified geometry.

## Geometry and Editing

- Expand irregular multi-room and junction workflows.
- Add explicit wall thickness and architectural reference-face editing.
- Improve structural reference measurement UX for columns and overhead beams.
- Continue collision-aware annotation and dense-plan interaction work.

## Synchronized 3D

- Generate an edited 3D scene from the authoritative precision document.
- Keep wall, opening, column, beam, and elevation revisions synchronized between 2D and 3D.
- Preserve the original RoomPlan USDZ as immutable source evidence.

## Photo Reconstruction

- Evaluate an on-device or controlled-service photogrammetry pipeline for existing PhotoScan drafts.
- Make reconstruction progress, failure, privacy, and storage behavior explicit.
- Add textured model validation before connecting results to architectural geometry.

## Professional Exchange

- Extend PDF reports with configurable schedules and measurement provenance.
- Evaluate DXF for dimensionally accurate 2D exchange.
- Evaluate IFC for BIM-oriented semantic exchange.
- Evaluate OBJ/FBX/USDZ for downstream visualization tools.
- Treat DWG interoperability as a compatibility/export project, not a renamed internal file.

No CAD, BIM, or reconstructed-model export listed above is implemented in the current release.

## Platform Quality

- Increase physical-device RoomPlan regression coverage.
- Add privacy review and data-retention controls before any cloud capability.
- Continue accessibility, localization, performance, and migration testing.
