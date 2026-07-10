# Releasing

Two independent version concepts — don't conflate them:

- **Mod semver** (`modversion=1.3.x` in both `mod.info` files) — bumped every release, must
  equal the git tag `vX.Y.Z`. `scripts/package.*` enforce tag == modversion.
- **Targeted PZ build** (`name=PlumbingFixed (B42.15)` in `42/mod.info`,
  `title=... [B42.15.2+]` in `workshop/workshop.conf`, and the "TESTED IN B42.15.2" line in
  `workshop/description.bbcode`) — changed only when you retarget a new game build. That's
  [UPDATING-PZ.md](UPDATING-PZ.md), not a normal release.

## Release checklist

1. **Bump** the mod semver:
   ```
   mise run bump 1.3.14
   ```
   (updates `modversion=` in `41/mod.info` and `42/mod.info`).
2. **Verify**: `mise run check`, then in-game SP + MP per [TESTING.md](TESTING.md).
3. **Update `workshop/description.bbcode`** (and `workshop/workshop.conf` if title/tags/
   visibility changed) if user-facing behavior changed.
4. **Commit** the version bump + changes.
5. **Package sanity** (optional, CI also does this): `mise run package v1.3.14` builds
   `./PlumbingFixed` and fails on any version mismatch.
   > `package` is the shared build step — CI (`release.yml`), `deploy`, and `publish` all go
   > through it. It has **twin** implementations, `scripts/package.sh` (Unix/CI) and
   > `scripts/package.ps1` (Windows); if you change one, change the other identically.
6. **Tag + GitHub release**: run the **Release Mod** GitHub Action
   (`.github/workflows/release.yml`, `workflow_dispatch`) with tag `v1.3.14`. It runs
   `scripts/package.sh`, zips `PlumbingFixed`, pushes the tag, and creates the GitHub release.
7. **Publish to Steam Workshop** (local, interactive). The target is **required** — publish
   to the **test** item, verify its page, *then* **prod**:
   ```
   mise run publish test "Short changenote"   # verify at the test item URL first
   mise run publish prod "Short changenote"   # only once test looks right
   ```

## Steam Workshop publish (`scripts/publish-workshop.{ps1,sh}`)

- **One-time:** `cp mise.local.toml.example mise.local.toml` and set `STEAM_USER` (git-ignored).
  steamcmd still prompts for the password + Steam Guard code — only the username is stored.
- **Target is required and explicit.** `mise run publish <test|prod> "note"` — there is **no
  default and no env fallback**, so you can't publish to prod by accident. The two ids live in
  `workshop/workshop.conf` (`published_id` = prod `3626008449`, `test_published_id` = test
  `3680940911`); override per-target with `PF_PUBLISHED_FILE_ID` / `PF_TEST_PUBLISHED_FILE_ID`
  (and `PF_APPID`) in `mise.local.toml` if you fork the item. Always do **test** and eyeball the
  page before **prod**.
- Requires **steamcmd** on PATH: `winget install Valve.SteamCMD` (winget id `Valve.SteamCMD`).
  Not a CI step — you run it locally so Steam Guard can prompt.
- It rebuilds `./PlumbingFixed`, writes `.publish/workshop.vdf`, then runs
  `steamcmd +login <user> +workshop_build_item <vdf> +quit`.
- **Source control is the source of truth for the Workshop page.** By default it pushes:
  - **content** = `./PlumbingFixed`
  - **preview image** = `workshop.conf` `preview=` (default `preview.png`) → `previewfile`
  - **title / tags / visibility** = from `workshop/workshop.conf` (flat `key=value`); tags are
    `;`-separated and converted to the VDF comma form, visibility word → steamcmd int.
  - **description** = `workshop/description.bbcode`, read **verbatim** and escaped into the VDF.

  So to change the Steam page, edit `workshop/description.bbcode` / `workshop/workshop.conf` /
  the preview image and re-publish — don't edit the page in-browser (a publish will overwrite it).
- **Preview it first** — behavior is driven by explicit flags, never ambient env. `mise run
  publish` always uploads, so to preview run the script directly with `--dry-run`:
  `pwsh -File scripts/publish-workshop.ps1 test "note" --dry-run` (or `bash
  scripts/publish-workshop.sh test "note" --dry-run`) builds + prints the VDF **without
  uploading** (works without steamcmd installed). Both twins accept the POSIX `--dry-run` /
  `--content-only`; the ps1 also accepts the native `-DryRun` / `-ContentOnly`. Dry-run with
  no target defaults to `test`; pass `prod` to preview the prod VDF. `--content-only` uploads
  files without touching title/description/tags/visibility.
- Set the Steam user via `-SteamUser you` or `$env:STEAM_USER`; otherwise it prompts.
- **Caveat:** only the single **preview** image is manageable via steamcmd. The extra
  gallery screenshots on the Workshop page are *not* settable this way — put images that
  should live in the description as `[img]<url>[/img]` BBCode (e.g. raw GitHub URLs) inside
  `workshop/description.bbcode`, as it already does. Verify the page after your first publish.
- **Not 100% certain from docs:** the VDF `tags` shape (comma string) and the `visibility` int
  mapping. The script logs exactly what it sends — confirm with `-DryRun`, then check the page
  after a real publish.

steamcmd is the only supported publish path. The in-game uploader (PZ → Workshop →
"Upload/Update mod") is **no longer supported** — it read `workshop.txt`, which we've dropped.

## After publishing

- Confirm the item at https://steamcommunity.com/sharedfiles/filedetails/?id=3626008449.
- The GitHub release zip is the offline/manual-install artifact.
