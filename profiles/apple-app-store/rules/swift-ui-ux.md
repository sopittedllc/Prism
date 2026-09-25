---
paths:
  - "**/*.swift"
  - "**/*.storyboard"
  - "**/*.xib"
  - "**/*.xcassets/**"
---

# Swift / Apple UI and UX Standard

Follow `docs/ui-ux/` and current Apple Human Interface Guidelines. State the target
platform; iOS, iPadOS, and macOS share frameworks but not identical navigation,
windowing, density, menu, pointer, or keyboard expectations.

## Composition and architecture

- Read the parent, siblings, navigation/window scene, model/view model, and every route
  to the same action before editing a view.
- Keep view bodies declarative and side-effect free. Move transformation, sorting,
  validation, persistence, networking, and long-running work to the appropriate owner.
- Establish one source of truth. Bind controls through the domain contract; avoid local
  state that can diverge from persisted or processing state.
- New settings use the authoritative typed registry described in the installed
  `STATE_REGISTRY.md`; presets never maintain a parallel handwritten property list.
- Model loading, empty, content, stale, partial, permission-denied, offline, error,
  success, cancellation, and retry states explicitly when reachable.
- Prefer semantic system controls, containers, navigation, commands, menus, toolbars,
  alerts, sheets, and text styles. Custom controls inherit the full responsibility for
  semantics, focus, keyboard, targets, contrast, state, and platform behavior.
- Do not use view identity changes as a routine refresh mechanism. Preserve focus,
  selection, scroll position, in-progress input, and async work across updates.

## Design system

- Typography, spacing, color/material, radius, icon size, motion, control size, and
  numeric formatting come from semantic tokens or platform semantics.
- Before changing a literal or modifier, inventory every instance with the same
  semantic role. Fix the authority or split an overloaded role; do not stack overrides.
- Build canonical previews/examples for each shared component across major states,
  appearances, text sizes, and representative content lengths.
- Avoid fixed frames for text-bearing content unless clipping is an explicit tested
  contract. Use layout priorities, wrapping, adaptive stacks/grids, safe areas, and
  readable content widths deliberately.

## Interaction and feedback

- Every interactive element has a visible affordance, hover/focus/pressed/disabled
  state where relevant, and immediate truthful feedback.
- Use `Button`, commands, menus, and standard gestures before raw gesture recognizers.
  Gestures have discoverable keyboard/control alternatives.
- Preserve standard shortcuts and platform conventions. Destructive operations support
  undo when possible; confirmation is reserved for meaningful irreversible consequence.
- Async actions prevent accidental duplication, show progress proportionate to delay,
  remain cancellable where meaningful, and keep user work safe on failure.
- Alerts are specific and actionable—not generic “Error” dialogs—and identify what
  happened, what remains safe, and the next step.

## Accessibility

- Verify name, role, value, state, hint only when necessary, custom actions, grouping,
  sort/traversal order, live announcements, and focus restoration.
- Do not duplicate visible labels in spoken output or hide actionable controls from the
  accessibility tree. Represent custom adjustable controls with adjustable semantics.
- All primary tasks work with VoiceOver and keyboard/Full Keyboard Access. Test Voice
  Control and Switch Control where applicable.
- Support Dynamic Type or appropriate macOS text scaling without critical truncation,
  overlap, or loss of actions. Test the largest required size.
- Do not encode meaning through color, position, sound, hover, or motion alone.
- Respect increased contrast, Reduce Motion, reduced transparency, differentiate
  without color, and media caption/transcript requirements as applicable.
- Meet current platform target-size guidance and provide sufficient separation; larger
  visual hit areas must not create overlapping or misleading hit regions.
- `UIViewRepresentable` and `NSViewRepresentable` bridges explicitly preserve platform
  accessibility and focus behavior.

## Platform adaptation

- iOS/iPadOS: safe areas, orientation, keyboard avoidance, pointer, multitasking,
  resizable windows, scene restoration, and destructive swipe alternatives.
- macOS: menus/commands, standard shortcuts, window resizing/restoration, first
  responder, focus rings, toolbar/sidebar/inspector behavior, contextual menus,
  multiwindow use, and compact pointer targets appropriate to the platform.
- Localize user-visible text; test long translations, pluralization, formatted units,
  bidirectional layout, dates/numbers, and truncation policy.

## Required evidence

- XCUITest or appropriate structural tests with stable semantic identifiers.
- Automated accessibility audit where supported, followed by real VoiceOver and
  keyboard traversal of the primary workflow.
- Screenshot matrix: major states, minimum/typical/maximum size, light/dark, increased
  contrast, largest text, long locale, RTL where supported, oldest/newest target.
- Runtime interaction on representative physical devices or macOS configurations.
- Measured launch, response, scrolling, resizing, and animation performance where the
  workflow is performance-sensitive.
