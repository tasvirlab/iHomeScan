# Development Guide

## Project Layout

| Path | Purpose |
|---|---|
| `MyApp/` | Application source, models, repositories, services, and feature views |
| `iHomeScanTests/` | Swift Testing unit and integration tests |
| `iHomeScanUITests/` | XCUITest scenarios |
| `DesignReference/` | Tracked visual reference assets used by the project |
| `Documentation/` | Existing stage and export design notes |
| `docs/` | Repository-facing architecture, development, feature, and roadmap documentation |

The local `iHomeScan-Reconstruction-Lab/` directory is a separate experimental workspace and is intentionally excluded from this repository.

## Environment

- Application deployment target: iOS 17.6
- Scheme: `iHomeScan`
- Project: `iHomeScan.xcodeproj`
- Primary UI: SwiftUI
- Persistence: SwiftData and application-support files

Use an Xcode version that supports the installed project format and target runtime. The active developer team and bundle identifier can be overridden locally if your signing environment differs.

## Building

Open the project in Xcode and build the `iHomeScan` scheme, or use:

```bash
xcodebuild build \
  -project iHomeScan.xcodeproj \
  -scheme iHomeScan \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
```

If that simulator is unavailable, choose an installed iPhone simulator in Xcode or replace the destination name.

## Testing

Run the full configured suite from Xcode with **Product → Test**. Command-line execution uses the same scheme:

```bash
xcodebuild test \
  -project iHomeScan.xcodeproj \
  -scheme iHomeScan \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro Max'
```

Unit tests use the Swift Testing framework. UI tests use XCUIAutomation and deterministic launch fixtures where required.

## Simulator and Device Responsibilities

The simulator is suitable for project navigation, persisted/sample plans, geometry editing, reports, localization, and PhotoScan gallery workflows. A simulator is not evidence that RoomPlan capture works on hardware.

Use a LiDAR-equipped iPhone or iPad to validate:

1. Capability and permission messaging.
2. Live RoomPlan capture.
3. CapturedRoom processing and USDZ export.
4. Save/reopen with real scan artifacts.
5. Camera-based PhotoScan capture.

## Data Safety

Do not commit simulator containers, Application Support content, captured rooms, photo drafts, local configuration, signing material, or credentials. The repository `.gitignore` covers conventional paths, but always inspect staged files before committing.

Original RoomPlan JSON and USDZ files produced for a user are application data, not source fixtures. Test fixtures must be deliberately non-sensitive and licensed for repository use.

## Geometry Conventions

- Canonical internal length unit: meters (`Double`)
- User-facing measurement unit: millimeters where the precision editor requests it
- Model geometry and viewport transforms remain separate
- Source scan artifacts are immutable
- `PrecisionPlanDocument` is authoritative for edited geometry
- Verified measurements are never silently altered to satisfy another edit
