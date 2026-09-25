# JUCE Toolchain Example

Adapt paths, generator, presets, formats, and validators to the pinned project.

| Task | Typical command |
|---|---|
| Configure | `cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug` |
| Build | `cmake --build build --config Debug --parallel` |
| Test | `ctest --test-dir build --build-config Debug --output-on-failure` |
| Release build | Configure/build with `Release` or a checked-in CMake preset |
| Validate | Format/platform-specific validator against the built artifact |

Prefer checked-in CMake presets once supported configurations are known.
