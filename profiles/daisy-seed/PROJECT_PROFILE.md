# Daisy Seed / libDaisy Project Profile

This profile is for Electrosmith Daisy Seed firmware, normally C/C++ with libDaisy.
Pin the exact board revision, carrier hardware, libDaisy version/commit, toolchain,
sample rate, block size, and boot method in `PROJECT.md` and `TOOLCHAIN.md`.

## Architecture

Keep three boundaries explicit:

```text
Controls / UI scanning -> parameter snapshot -> audio callback
                                             -> domain DSP
Hardware drivers       -> board abstraction -> application
```

- DSP should be testable on the host without GPIO or codec hardware when practical.
- Centralize pin assignments, polarity, ADC ranges, mux channels, calibration, and
  units in a board definition; verify them against the exact schematic/revision.
- Pass control state to the callback through a bounded snapshot or other documented
  lock-free strategy. Do not share casually mutable state.

## Hard real-time callback

Unless an official API explicitly guarantees otherwise, the audio callback must not:

- allocate/free memory;
- lock or wait;
- perform file, console, USB, display, flash, or blocking peripheral I/O;
- throw exceptions or use unbounded algorithms;
- initialize resources lazily;
- perform work whose worst-case cost is unknown.

Preallocate buffers and DSP objects. State sample/block units. Smooth user parameters
where discontinuities can click. Define denormal, NaN/Inf, clipping, and bypass
behavior. Measure callback load with release optimization on hardware.

## Hardware and recovery safety

- Verify power, analog voltage ranges, pin capabilities, and peripheral conflicts
  before wiring or enabling outputs.
- Initialize outputs to a safe state before enabling audio/control paths.
- Debounce/smooth controls outside the audio callback when possible.
- Do not flash, erase external memory, change boot configuration, or install a
  toolchain without explicit user permission.
- Before risky firmware work, document how to enter the bootloader and restore a known
  good image.
- Do not claim hardware validation from host tests or a successful compile.

## Minimum verification matrix

- Host-side DSP unit tests: silence, impulse, nominal signal, extremes, NaN/Inf policy.
- Debug and release firmware builds from a clean state.
- Static size report: flash, SRAM, external memory where applicable.
- On-board smoke test: boot, audio I/O, every connected control, safe bypass/mute.
- Stress/soak test at the configured sample rate/block size with CPU headroom measured.
- Power cycle and reconnect behavior; bootloader/recovery path confirmed.
- Audio capture or objective measurement for the acceptance criteria (noise, gain,
  latency, frequency response, artifacts) rather than “sounds right” alone.
- Enforce flash/RAM budgets and fail builds when the accepted margin is exceeded.
- Measure stack high-water, callback deadline misses, underruns, and worst-case CPU;
  averages alone are insufficient for real-time safety.
- Use watchdog/fault telemetry that survives long enough to diagnose reset causes.
- Test malformed/non-finite control state and recover to bounded safe output.
- Maintain a known-good firmware image and automate rollback in the hardware fixture.
- Share the pure DSP core with host tests so reference vectors exercise the same code.

Record exact hardware revision and test conditions with results.
