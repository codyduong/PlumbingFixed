# Releasing

Two independent version concepts — don't conflate them:

- **Mod semver** (`modversion=1.3.x` in both `mod.info` files) — bumped every release, must
  equal the git tag `vX.Y.Z`. `scripts/package.*` enforce tag == modversion.
- **Targeted PZ build** (`name=PlumbingFixed (B42.15)` in `42/mod.info`, and
  `[B42.15.2+]` / "TESTED IN B42.15.2" in `workshop.txt`) — changed only when you retarget a
  new game build. That's [UPDATING-PZ.md](UPDATING-PZ.md), not a normal release.

## Release checklist

1. **Bump** the mod semver:
   ```
   mise run bump 1.3.14
   ```
   (updates `modversion=` in `41/mod.info` and `42/mod.info`).
2. **Verify**: `mise run check`, then in-game SP + MP per [TESTING.md](TESTING.md).
3. **Update `workshop.txt`** description/changenote text if user-facing behavior changed.
4. **Commit** the version bump + changes.
5. **Package sanity** (optional, CI also does this): `mise run package v1.3.14` builds
   `./PlumbingFixed` and fails on any version mismatch.
   > `package` is the shared build step — CI (`release.yml`), `deploy`, and `publish` all go
   > through it. It has **twin** implementations, `scripts/package.sh` (Unix/CI) and
   > `scripts/package.ps1` (Windows); if you change one, change the other identically.
6. **Tag + GitHub release**: run the **Release Mod** GitHub Action
   (`.github/workflows/release.yml`, `workflow_dispatch`) with tag `v1.3.14`. It runs
   `scripts/package.sh`, zips `PlumbingFixed`, pushes the tag, and creates the GitHub release.
7. **Publish to Steam Workshop** (local, interactive):
   ```
   mise run publish "Short changenote for this update"
   ```

## Steam Workshop publish (`scripts/publish-workshop.{ps1,sh}`)

- **One-time:** `cp mise.local.toml.example mise.local.toml` and set `STEAM_USER` (git-ignored).
  steamcmd still prompts for the password + Steam Guard code — only the username is stored.
  You can also override `PF_PUBLISHED_FILE_ID` / `PF_APPID` there if you fork the item.
- Requires **steamcmd** on PATH (https://developer.valvesoftware.com/wiki/SteamCMD). Not a CI
  step — you run it locally so Steam Guard can prompt.
- It rebuilds `./PlumbingFixed`, writes `.publish/workshop.vdf`
  (`appid 108600`, `publishedfileid 3626008449`, `contentfolder`, `previewfile`,
  `changenote`), then runs `steamcmd +login <user> +workshop_build_item <vdf> +quit`.
- By default it updates **content + preview + changenote only** and leaves the Steam page
  title/description untouched (the workshop.txt description uses BBCode that's easier to
  manage on the page / via the in-game uploader). Pass `-UpdateText` to also push the title.
- Set the Steam user via `-SteamUser you` or `$env:STEAM_USER`; otherwise it prompts.

If steamcmd isn't set up, the historical fallback still works: open PZ → Workshop →
"Upload/Update mod", which reads `workshop.txt` and the built content (clickops).

## After publishing

- Confirm the item at https://steamcommunity.com/sharedfiles/filedetails/?id=3626008449.
- The GitHub release zip is the offline/manual-install artifact.
