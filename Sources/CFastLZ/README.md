# FastLZ source provenance

`fastlz.c` and `include/fastlz.h` originate from
[ariya/FastLZ](https://github.com/ariya/FastLZ) commit
`b1342dabcf5257ab303743c9332fe75e9147a011` (FastLZ 0.5.0).
The upstream MIT terms are retained in `LICENSE.MIT` and in both source headers.
Prism uses only `fastlz_decompress` to inspect bounded public Kontakt metadata.
Prism locally hardened decompression input-length and match-distance checks in
`fastlz.c` after an AddressSanitizer reproduction of an out-of-bounds read on a
truncated level-2 stream. The upstream MIT attribution remains intact.
