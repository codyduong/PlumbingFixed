# Releasing

Two independent version concepts — don't conflate them:

- **Mod semver** (`modversion=1.3.x` in both `mod.info` files) — bumped every release, must
  equal the git tag `vX.Y.Z`. `scripts/package.*` enforce tag == modversion.
- **Targeted PZ build** (`name=PlumbingFixed (B42.15)` in `42/mod.info`, and the
  `title=... [B42.x+]` / "TESTED IN B42.x" lines in `workshop/workshop.vdf`) — changed only
  when you retarget a new game build. That's
  [UPDATING-PZ.md](UPDATING-PZ.md), not a normal release.

## Release checklist

1. **Bump** the mod semver:
   ```
   mise run bump 1.3.14
   ```
   (updates `modversion=` in `41/mod.info` and `42/mod.info`).
2. **Verify**: `mise run check`, then in-game SP + MP per [TESTING.md](TESTING.md).
3. **Update `workshop/workshop.vdf`** (title / description / tags) if user-facing
   behavior changed.
4. **Commit** the version bump + changes.
5. **Package sanity** (optional, CI also does this): `mise run package v1.3.14` builds
   `dist/PlumbingFixed` and fails on any version mismatch.
   > `package` is the shared build step — CI (`release.yml`), `deploy`, and `publish` all go
   > through it. It has **twin** implementations, `scripts/package.ps1` (local dev) and
   > `scripts/package.sh` (CI-only, the repo's sole .sh script); if you change one, change
   > the other identically.
6. **Tag + GitHub release**: run the **Release Mod** GitHub Action
   (`.github/workflows/release.yml`, `workflow_dispatch`) with tag `v1.3.14`. It runs
   `scripts/package.sh`, zips `dist/PlumbingFixed`, pushes the tag, and creates the GitHub release.
7. **Publish to Steam Workshop** (local, interactive). The target is **required** — publish
   to the **test** item, verify its page, *then* **prod**:
   ```
   mise run publish test "Short changenote"   # verify at the test item URL first
   mise run publish prod "Short changenote"   # only once test looks right
   ```

## Steam Workshop publish (`scripts/publish-workshop.ps1`)

- **One-time:** `cp mise.local.toml.example mise.local.toml` and set `STEAM_USERNAME` +
  `STEAM_PASSWORD` (git-ignored; the password is age-encrypted — see
  [LESSONS-LEARNED.md](LESSONS-LEARNED.md)). `mise run publish` logs in non-interactively.
- **Target is required and explicit.** `mise run publish <test|prod> "note"` — there is **no
  default and no env fallback**, so you can't publish to prod by accident. The two item ids are
  baked into the publish scripts (`test` = `3680940911`, `prod` = `3626008449`). Always do
  **test** and eyeball the page before **prod**.
- Requires **steamcmd** on PATH: `winget install Valve.SteamCMD` (winget id `Valve.SteamCMD`).
- It rebuilds `dist/PlumbingFixed`, fills `workshop/workshop.vdf` into `.publish/workshop.vdf`,
  then runs `steamcmd +login <user> +workshop_build_item <vdf> +quit`.
- **`workshop/workshop.vdf` is the source of truth for the Workshop page** — a steamcmd
  KeyValues file stored **verbatim** (title, description with real newlines, tags, appid,
  content). The scripts only substitute the dynamic fields: `{{PUBLISHEDFILEID}}` and
  `{{VISIBILITY}}` (per target — prod is public, test is unlisted), `{{CONTENTFOLDER}}` +
  `{{PREVIEWFILE}}` (built absolute paths), and `{{CHANGENOTE}}`.
  To change the Steam page, edit `workshop/workshop.vdf` and re-publish — don't edit the page
  in-browser (a publish overwrites it).
- **Preview it first.** `mise run publish` always uploads, so to preview run the script directly:
  `pwsh -File scripts/publish-workshop.ps1 test "note" -DryRun` builds + prints the VDF
  **without uploading** (works without steamcmd installed). With no target, dry-run defaults
  to `test`; pass `prod` to preview the prod VDF.
- Set the Steam user via `-SteamUser you` or `$env:STEAM_USERNAME`; otherwise it prompts.
- **Caveat:** only the single **preview** image is manageable via steamcmd. The extra
  gallery screenshots on the Workshop page are *not* settable this way — put images that
  should live in the description as `[img]<url>[/img]` BBCode (e.g. raw GitHub URLs) inside the
  `description` value of `workshop/workshop.vdf`. Verify the page after your first publish.

steamcmd is the only supported publish path. The in-game uploader (PZ → Workshop →
"Upload/Update mod") is **no longer supported** — it read `workshop.txt`, which we've dropped.

## After publishing

- Confirm the item at https://steamcommunity.com/sharedfiles/filedetails/?id=3626008449.
- The GitHub release zip is the offline/manual-install artifact.
