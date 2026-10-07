# Kontakt instrument-use controls in Ableton Live

Read-only isolated controls on 2026-10-04 used Live 12.4.6 and Kontakt 8. One saved
set had an Accordion NKI loaded, a second replaced it with Action Strikes Hits,
and a third removed Hits while its browser row remained selected. The original
control set and installed content were unchanged. Private sets and screenshots
remain outside the repository; their paths and payloads are not product data.

Live stores the Kontakt VST3 ProcessorState inside its compressed set XML. The
existing public NIS reader found product ID `P44` in the Accordion state, `225`
in the Hits state, and neither after removal. Those IDs establish product-level
saved state for these controls, not exact active NKI membership. The nested loaded
payloads were opaque to the verified public FastLZ reader and contained no plain
exact NKI name in ASCII or UTF-16LE. After removal, the decodable inner program
was the blank default. A visible selected browser row therefore cannot stand in
for a loaded instrument.

A separate existing unprotected Kontakt control contains an exact NKI path in its
public filename table. That proves exact-path extraction is possible in a subset;
active Program-to-path ownership still needs multi-instrument, replacement and
removal controls before the path can become patch-use evidence.

Instrument Last Used remains unknown unless a source names an exact instrument
and an independently qualified load or restore time. Set modification time,
plugin restoration, product ID, and browser selection cannot be copied to every
instrument. These controls set a concrete negative boundary for all four host
adapters and motivate a documented active-patch API or validated unprotected
export path for general coverage. SINE saved inclusion likewise does not supply a
per-instrument last-use event on its own.
