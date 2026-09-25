# Apple App Store Toolchain Example

Prefer a checked-in Xcode project/workspace and shared scheme. Replace placeholders
with exact project values and use argument arrays in `.workflow/toolchain.json`.

| Task | Typical tool |
|---|---|
| Build/test | `xcodebuild` with explicit workspace/project, scheme, configuration, destination, and result bundle |
| Static analysis | `xcodebuild analyze` |
| Archive | `xcodebuild archive` with an explicit archive path |
| Export | `xcodebuild -exportArchive` with reviewed export options |
| Inspect signing | `codesign`, `security cms`, and provisioning-profile inspection |
| Validate upload | Current Apple-supported validation workflow for the target |
| UI/accessibility | XCTest/XCUITest plus physical-device checks |

Uploading, signing with protected credentials, TestFlight distribution, and submission
remain tier-3 actions.
