# Precision Export — Technical Design Note

**Status: proposal.** iHomeScan already generates PDF measurement reports. The extended precision export pipeline described here, including DXF, DWG, IFC, OBJ, FBX, and regenerated USDZ, is **not implemented**.

## Export Source of Truth

Future exporters should read an immutable `PrecisionExportSnapshot` derived from `PrecisionPlanDocument.currentPlan`, rather than directly querying SwiftUI or SwiftData view state. The snapshot should preserve:

- Canonical dimensions in meters (`Double`)
- Projects, floors, rooms, and stable element identifiers
- Walls, openings, columns, and beams
- Elevation, measurement provenance, and completeness
- Coordinate reference, origin, axis conventions, revision, and export timestamp

Original RoomPlan JSON and USDZ files must remain unchanged.

## Proposed Pipeline

`PrecisionPlanDocument → ExportSnapshotBuilder → ExportValidator → FormatAdapter → AtomicFileWriter`

The validator should reject non-finite coordinates, invalid geometry, and missing format-required values. Warnings must remain visible when details are incomplete. All outputs must define units and coordinate transforms explicitly.

## Format Considerations

| Format | Proposed role | Key requirements |
|---|---|---|
| Enhanced PDF | Scaled plans, schedules, dimension chains, provenance | A4/A3, page scale, calibration line, consistent area policy |
| DXF | First CAD interchange format | Layers for walls/openings/structural elements/dimensions; explicit `INSUNITS` |
| DWG | Proprietary CAD interoperability | Evaluate licensed SDK or verified conversion; do not hand-roll a purported DWG writer |
| IFC | BIM exchange | Semantic entities, stable GUID mapping, accurate storeys and openings; never invent unknown structural data |
| OBJ/MTL | DCC mesh exchange | Units, triangulation, material groups, and clear limits on semantic preservation |
| FBX | DCC hierarchy/material exchange | Evaluate SDK licensing and feasible platform implementation |
| USDZ | Updated Apple 3D visualization | Rebuild from the edited parametric model without overwriting source capture |

## Coordinates and Validation

- Keep internal lengths in meters and record all output unit conversions.
- Define floor elevations, local/project origins, and axis transformations.
- Preserve stable element IDs where the exchange format permits it.
- Test lengths, openings, orientation, and placement after round-trip import.
- Keep UI transformations separate from persisted geometry and export transforms.

## Suggested Implementation Order

1. Export snapshot schema and validator.
2. Enhanced PDF measurement report.
3. DXF exporter and AutoCAD round-trip testing.
4. IFC exporter and Revit interoperability testing.
5. Mesh/scene exports: OBJ and edited USDZ.
6. DWG/FBX feasibility, licensing, and implementation.
7. Export UI, progress, cancellation, and sharing.

## Acceptance Criteria

- A 1,000 mm reference dimension imports as 1,000 mm within the stated tolerance.
- Non-rectangular rooms retain their geometry.
- Doors, windows, columns, and beams retain valid placement and identifiers where supported.
- PDF area calculations use the same documented policy as the editor.
- Missing measurements are not fabricated.
- Export never mutates original RoomPlan artifacts.
- Target-application round trips are verified before claiming format support.
