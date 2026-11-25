# Roadmap

Planned engineering directions for iHomeScan. None of these items should be interpreted as shipped functionality.

## 1. Measurement and Geometry

- Integrate selected existing Bluetooth laser distance meters; keep manual measurements available.
- Record device-origin measurements separately from user-declared values, including provenance and uncertainty where supported.
- Improve irregular layouts, cross-wall constraints, and dense-plan dimension-label placement.

## 2. Architectural Editing and 3D

- Extend wall-reference and structural-element measurement workflows.
- Generate a 3D scene from the edited parametric plan while preserving the original RoomPlan USDZ.
- Validate edited walls, openings, columns, beams, and elevations consistently in 2D and 3D.

## 3. Professional Outputs

- Improve dimensioned PDF reports and schedules.
- Evaluate DXF for measured 2D exchange, followed by IFC and other formats based on interoperability tests.
- Define export coordinates, units, geometry validation, and round-trip acceptance tests before adding formats.

A more detailed [precision export design note](../Documentation/PrecisionExportRoadmap.md) describes the proposed interfaces and format-specific requirements.

## 4. Photo Reconstruction and Platform Quality

- Evaluate a privacy-conscious reconstruction pipeline for PhotoScan drafts; no Core ML/photo-to-3D pipeline currently exists.
- Complete physical-device capture validation and reliable simulator test execution.
- Improve accessibility, localization, performance, migration coverage, and privacy controls as needed.
