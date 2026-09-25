---
paths:
  - "**/*.{cpp,cc,cxx,h,hpp}"
  - "**/CMakeLists.txt"
---

# JUCE VST3 / Audio Unit UI and UX Standard

Follow `docs/ui-ux/`. A plug-in editor is a guest inside many hosts, display scales,
window managers, workflows, and automation models. Validate behavior in representative
VST3 and AU hosts; the standalone target is not sufficient.

## Product workflow and hierarchy

- Define the musician/engineer's primary jobs: initialize, understand signal flow,
  shape sound, compare, automate, save/recall, recover, and work quickly under session
  pressure. Optimize those flows rather than maximizing visible controls.
- Organize controls by audible signal flow and task. Make the most consequential sound
  controls dominant; keep metering/status legible but secondary to manipulation.
- Use consistent semantic groups, alignment, label position, units, precision, bipolar
  treatment, default indication, reset behavior, and modulation/automation feedback.
- Advanced sections remain discoverable and preserve state without destabilizing the
  main layout. Do not hide essential state behind hover alone.

## Parameter contract

- Every automatable UI control maps through the stable processor parameter contract,
  not direct DSP mutation. Processor behavior remains correct with the editor closed.
- Parameters and non-parameter settings follow the installed `STATE_REGISTRY.md`; the
  preset system serializes authoritative state instead of copying a manual subset.
- Use attachments or an equally explicit lifetime-safe synchronization mechanism.
  Declare construction/destruction order so parameters, controls, and attachments do
  not outlive one another.
- Gestures correctly bracket host automation edits. UI updates from host automation do
  not create feedback loops, fight active gestures, or allocate/block the audio thread.
- Display text, parsing, units, normalization, skew, step count, default, reset, and
  automation identity agree with the processor and host-visible parameter contract.
- Distinguish default, current, automated, modulated, disabled, unavailable, and clipped
  states without color alone.

## Editor lifecycle and host behavior

- Editor construction/open/close is repeatable and does not change sound or state.
- Support declared minimum/maximum size, aspect behavior, host-driven resize, saved
  editor size, and every scale factor promised by the product. Use constrained resize;
  never assume a single pixel density or standalone window behavior.
- Test rapid open/close, multiple instances, session reopen, host scan/rescan, offline
  render, focus transfer to/from host, host keyboard shortcuts, modal/popup dismissal,
  and context-menu behavior.
- Do not capture host shortcuts indiscriminately. Text entry and focused controls
  consume only intended keys; tab/shift-tab traversal is predictable.
- Integrate host-provided parameter context menus where the format/host supports them,
  preserving automation/MIDI-learn affordances.
- AUv3 UI may be hosted out of process and requested asynchronously. Do not assume
  in-process lifetime, block the main thread, or depend on standalone-only resources.

## JUCE composition and rendering

- Shared appearance comes from semantic LookAndFeel/style tokens and canonical
  components, not scattered `paint` literals. Inventory every semantic consumer before
  changing LookAndFeel behavior.
- `resized()` produces valid nonoverlapping bounds at every supported size. Define
  collapse/reflow priorities rather than uniformly scaling illegible controls.
- Cache expensive static geometry/assets appropriately, but update theme/scale/state
  correctly. Repaint only necessary regions and throttle meters/animations to a stated
  UI rate independent of the audio callback.
- Never allocate, lock, log, access UI objects, or perform message-thread work from the
  audio callback. Transfer meter/state snapshots through a bounded real-time-safe path.
- Verify embedded fonts/assets licensing, fallback, missing-resource behavior, scale,
  and localization. Raster assets need appropriate resolution or vector alternatives.

## Accessibility and input

- Prefer JUCE controls with native accessibility support. Custom components provide an
  appropriate `AccessibilityHandler`, role, title/description, current value/state,
  actions, focusability, and change notifications.
- Every parameter is operable without precise dragging: keyboard adjustment, typed
  entry or accessible value action as appropriate, default reset, and coarse/fine
  control discoverability.
- Define keyboard focus containers and traversal deliberately. Focus is visible, not
  lost behind overlays, restored after dialogs, and compatible with host focus.
- Provide sufficient target size/spacing for the intended density and input devices.
  Knob graphics do not imply that circular dragging is the only usable interaction.
- Contrast, color-blind differentiation, zoom/scale, reduced motion where available,
  non-audio status equivalents, and readable numeric values are required.
- Tooltips supplement visible labels; they do not carry essential identity or state.

## States, presets, and errors

- Design initialized/default, loading, ready, automated, bypassed, disabled, clipped,
  missing resource, incompatible state, corrupt preset, save failure, and recovery.
- Preset browsing exposes modified/dirty state, save destination, overwrite consequence,
  migration error, and restored result. Never silently discard edits on preset/session
  changes.
- Meters define range, scale, peak/hold/clipping semantics, decay, silence, and reset.
  Visual response is useful at host-relevant frame rates without implying sample-level
  precision it does not display.

## Required evidence

- Systemic inventory and representative component gallery for semantic controls.
- Screenshot matrix at min/typical/max editor sizes, all promised host scale factors,
  light/dark/theme variants, every major state, and long labels/values.
- Keyboard-only and platform screen-reader walkthrough on macOS and Windows when
  supported, including host/editor focus boundaries.
- VST3 and AU validation plus runtime tests in at least two materially different hosts
  per shipped platform, covering resize, automation, context menus, preset/session
  recall, multiple instances, editor reopen, and offline render.
- Measured editor-open latency, resize/repaint smoothness, meter CPU, memory, and proof
  that UI activity does not cause audio-thread allocations or deadline misses.
