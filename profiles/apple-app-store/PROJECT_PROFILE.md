# Apple App Store Project Profile

This profile covers iOS, iPadOS, macOS, watchOS, tvOS, and visionOS applications
distributed through App Store Connect. Pin the Xcode/Swift versions, deployment
targets, devices, architectures, bundle identifiers, capabilities, and supported OS
versions. Treat current App Review and upload requirements as externally changing:
verify them against Apple documentation before every release.

## Boundaries and state

Separate presentation, domain logic, persistence, networking/platform services, and
App Store concerns through testable contracts. State must have a documented owner and
execution context. UI code does not perform persistence, networking, purchasing, or
other blocking work directly.

Define and test:

- launch, background/foreground, suspension, termination, restoration, and low-memory
  behavior;
- offline, slow, interrupted, denied-permission, and service-failure behavior;
- cancellation, retry, idempotency, and duplicate-event handling;
- data-model and settings migration from every supported released version;
- multiple windows/scenes, rotation, size classes, display scaling, and platform input
  modes where applicable;
- locale, calendar, time zone, right-to-left layout, Dynamic Type, VoiceOver,
  keyboard navigation, reduced motion, contrast, and accessibility labels/actions;
- account deletion, export, retention, consent, and privacy behavior when applicable.

## Platform and store contracts

- Every capability and entitlement must be necessary, least-privileged, present in the
  intended target, and consistent with signing/provisioning and store metadata.
- Usage-description strings explain the user benefit before a protected resource is
  requested. Denial and later Settings changes must be recoverable.
- Maintain an accurate privacy manifest, collected-data declarations, tracking policy,
  and required-reason API declarations for the app and included SDKs.
- Inventory third-party SDKs, licenses, privacy manifests/signatures, binary contents,
  network destinations, and update provenance.
- StoreKit behavior must cover pending, cancelled, interrupted, restored, revoked,
  refunded, expired, offline, duplicate, and family-sharing cases as applicable.
- App metadata, screenshots, previews, age rating, export-compliance answers, review
  notes, demo credentials, support URL, privacy URL, and in-app behavior must agree.
- Never automate certificate/key creation, signing-credential access, upload,
  TestFlight distribution, phased release, pricing, or App Review submission without
  explicit tier-3 authorization.

For macOS, distinguish Mac App Store distribution from Developer ID distribution and
notarization. Do not apply one channel's signing, sandbox, entitlement, or packaging
assumptions to the other.

## Required verification matrix

- Clean Debug and Release archive builds with warnings treated according to policy.
- Unit, integration, UI, launch-performance, migration, and failure-path tests.
- Static analysis plus Address/Thread/Undefined Behavior sanitizers where supported.
- Physical-device testing on the oldest and newest supported OS/device classes;
  simulators supplement but do not replace representative devices.
- Fresh install, update from released versions, restore, uninstall/reinstall, offline
  launch, permission denial/regrant, backgrounding, memory pressure, interruption, and
  crash-relaunch recovery.
- Accessibility audit, localization/pseudolocalization, clipping, dark/light mode,
  large content sizes, keyboard and assistive input.
- Performance budgets for launch, hangs, memory, energy, storage, network, scrolling,
  and critical interactions using Release builds.
- Archive inspection: bundle IDs, versions, architectures, embedded frameworks,
  entitlements, privacy manifests, symbols, signing, and prohibited/private API checks.
- StoreKit tests and sandbox/TestFlight testing where monetization exists.
- App Store upload validation before an authorized upload, followed by processed-build
  warning review. TestFlight evidence precedes production submission.
- Release rollback/mitigation plan, staged rollout decision, monitoring, support, and
  an incident path for crashes, hangs, data loss, and review rejection.

An archive or passing simulator test suite is not proof of App Store readiness.
