# JUCE Audio Plug-in Project Profile

This profile is for C++ audio plug-ins using JUCE. Pin the JUCE version/commit, CMake
version, compiler, plugin formats, operating systems, architectures, and supported
hosts in `PROJECT.md` and `TOOLCHAIN.md`.

## Architecture

Keep the processor independent of the editor:

```text
Host automation/state -> stable parameter model -> processor/DSP
Editor/control UI      -> stable parameter model
Host audio/MIDI        -> processor/DSP -> host output
```

- The processor must work correctly with no editor open and in headless rendering.
- Treat parameter IDs, types, ranges, normalization/skew, defaults, units, and ordering
  as persistent public API. Do not rename/reorder them casually after release.
- Version serialized state and define migration/failure behavior.
- Keep DSP separable enough for deterministic unit tests without a plugin host.

## Audio-thread contract

The processing callback must not allocate, lock, block, log, touch UI objects, perform
file/network I/O, or do unbounded work. Allocate in preparation, handle arbitrary
documented block sizes, and treat channel/bus layout as runtime input.

Define and test:

- sample-rate and block-size changes;
- zero and unusual block sizes supported by the framework/host;
- mono, stereo, and declared sidechain/bus layouts;
- parameter automation at block and sample granularity as the design requires;
- MIDI event offsets and ordering when MIDI is supported;
- bypass, tail length, latency reporting, and latency changes;
- denormals, silence, NaN/Inf policy, clipping, and state reset;
- concurrent host calls and editor open/close lifetime.

## UI and state

- UI reads/writes through the parameter/state contract, never by mutating DSP internals.
- Attachments/listeners need explicit lifetime and message-thread ownership.
- Test DPI/scaling, resizing, keyboard access, and rapid editor open/close.
- Saving/restoring a session must reproduce audible state without requiring the editor.

## Minimum verification matrix

- DSP unit tests with deterministic signals and numeric tolerances.
- Clean debug and release builds for every shipped format/architecture.
- JUCE unit tests or project-specific test runner.
- A current plug-in validation tool appropriate to each format/platform.
- Smoke tests in at least two materially different representative hosts.
- Offline render and real-time playback comparison where applicable.
- Automation recording/playback, preset/state recall, duplicate instances, editor
  open/close, sample-rate/block-size changes, and non-default bus layouts.
- CPU/allocation measurement in release builds and a multi-instance stress test.
- Packaging/signing/notarization validation when distributed.
- Allocation traps around the processing callback and deterministic golden signal
  vectors with stated floating-point tolerances.
- Address, undefined-behavior, and thread sanitizers where the platform/host permits.
- State migration tests from every released schema and unknown/future/corrupt state.
- Format-specific validation such as the current official/vendor validator, with all
  warnings classified rather than ignored.
- Host crash/restart, scan, rescan, duplicate instance, freeze/bounce, and session
  reopen tests using clean user-state directories.
- Explicit automation tests for parameter identity, normalization, gestures, and
  sample-accurate behavior promised by the product.

A standalone target is useful, but it does not substitute for plugin-host validation.
