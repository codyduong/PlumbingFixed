# `vendor/pz/` — vanilla baseline for the update process

This holds the **verbatim vanilla source of only the functions PlumbingFixed overrides**,
snapshotted per Project Zomboid build under `vendor/pz/<VERSION>/`. It is the *ancestor* we
3-way merge our overrides against when the game updates — see [docs/UPDATING-PZ.md](../../docs/UPDATING-PZ.md).

- `VERSION` — the PZ build the baseline currently reflects.
- `overrides.manifest` — which vanilla files/functions we shadow (source of truth).
- `<VERSION>/…` — extracted subsets, mirroring the game's `media/lua` tree. **Generated — do
  not hand-edit.** Regenerate with `mise run vanilla-extract`; see drift with `mise run vanilla-diff`.

Only the functions we already fork are stored here (the same code we ship as modified copies),
not whole vanilla files. This code is © The Indie Stone; it lives here solely as a
development baseline for reconciling updates.
