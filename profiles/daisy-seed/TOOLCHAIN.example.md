# Daisy Seed Toolchain Example

Adapt these only after checking the chosen libDaisy project layout and pinned version.

| Task | Typical command |
|---|---|
| Build firmware | `make` |
| Clean build | `make clean && make` |
| Program via DFU | `make program-dfu` |
| Size report | ARM toolchain `size` on the produced ELF |
| Host DSP tests | Project-specific CMake/CTest command |

Flashing is a user-authorized runtime action, never an automatic verification step.
