# Visual and Interaction Test Matrix

Every UI plan selects applicable dimensions. Pairwise coverage is acceptable for
low-risk combinations; critical workflows need explicit boundary coverage.

| Dimension | Required candidates |
|---|---|
| State | empty, loading, nominal, populated, error, offline, disabled, success |
| Size | minimum, typical, maximum; narrow/tall and wide/short boundaries |
| Appearance | light, dark, increased contrast, reduced transparency if supported |
| Text | default, largest supported/accessibility size, long localized strings, RTL |
| Input | pointer/touch, keyboard-only, screen reader, domain controller/automation |
| Data | none, one, typical, maximum credible, malformed/stale/partial |
| Lifecycle | first launch/open, resume/reopen, background/close, interrupted operation |
| Device/host | oldest/newest supported OS, representative displays, required DAWs/formats |
| Scale | platform display scaling and plug-in host scale factors |

## Screenshot protocol

- Use deterministic fixtures, locale, appearance, scale, window/editor size, and seed.
- Capture the whole composition and targeted details when needed.
- Mask only nondeterministic regions and document every mask.
- Store reference metadata: task, content fingerprint, target, OS/host, scale, state.
- Pixel diffs identify change; a UX reviewer decides whether the change is correct.
- Never update references automatically merely because a diff exists.

## Interaction protocol

For each critical flow record action, expected transition, observed transition,
feedback latency, focus destination, undo/recovery, and retained state after reopen.

Audit regression additions: reading-progress includes populated table and pending
reference inspector; setup-long-folders exercises10 roots, Remove focus and
740pt sheet bound; setup-save-error retains all recovery actions; plugins-dark
uses a long instrument name; table alignment rects assert8pt horizontal padding
and vertical centering. Compare captures visually; no pixel-diff certification.
