# Timewarrior launcher provider

Control [Timewarrior](https://timewarrior.net/) from the Noctalia launcher.

Type `>tw` in the launcher to get:

- **Tracking / Not tracking** — live status; while active the elapsed time
  counts up and the tags are shown.
- **Start: &lt;tags&gt;** — appears when you type tags after `>tw` (e.g.
  `>tw client meeting`). Starts tracking; if something is already tracked,
  Timewarrior stops it first, so this doubles as "switch task".
- **Stop** / **Cancel** — shown while tracking (record vs. discard).
- **Continue** — shown while idle; resumes the most recently closed interval.

## Requirements

- `timew` on `PATH`.
- To use a relocated database, launch Noctalia with `TIMEWARRIORDB` set in its
  environment — the plugin intentionally does not set it, so it respects
  whatever your session configures.
