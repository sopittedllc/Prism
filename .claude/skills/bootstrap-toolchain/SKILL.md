---
name: bootstrap-toolchain
description: Discover, verify, and configure the project's exact build/test/static-analysis commands before feature work begins.
disable-model-invocation: false
---

Inspect manifests, lockfiles, build projects, shared schemes/presets, installed tools,
and the selected profile. Use the researcher for version-specific uncertainty. Propose
exact argument arrays for `.workflow/toolchain.json`, run each safe check, and retain
only commands that work from the repository root. Never install dependencies, flash,
sign, upload, or weaken a check merely to make bootstrap pass. Mark unavailable
target-only checks as blocked with a concrete provisioning plan. Update `TOOLCHAIN.md`
to match the verified executable configuration. If a required trusted registry or
documentation host is absent from the sandbox allowlist, propose the narrow domain
addition as one explicit setup approval rather than repeatedly asking during builds.
