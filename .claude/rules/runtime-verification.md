# Runtime verification

A successful build does not validate observable behavior. Changes involving UI,
audio, timing, hardware, files, services, plugin hosts, or OS integration require a
running-artifact check on a representative target.

After such a change, report automated evidence and give a short, change-specific
manual checklist for anything the agent cannot exercise. Do not call the work
complete while a required runtime check is blocked or awaiting user confirmation.
