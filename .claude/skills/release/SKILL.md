---
name: release
description: Cut a new testnod-uploader-action version. Pick the next semver tag, run pre-release gates, create a signed tag, push it and move the floating major tag (v1) only when every gate passes and the user confirms, then publish the GitHub Release. Use when the user asks to release, bump the version, tag, or ship the action.
argument-hint: "[patch|minor|major|vX.Y.Z]"
disable-model-invocation: true
---

# Release testnod-uploader-action

The version lives in git tags. There's no version constant or changelog to update. Each release has two tags:
- **`vX.Y.Z`**: a signed, annotated tag that never moves.
- **`vMAJOR`** (today `v1`): a floating tag that points at the latest release in that major.

Most workflows use `testnod/testnod-uploader-action@v1`. When `v1` moves, every one of them runs the new `action.yml` on its next run. No workflow runs on tags, so nothing builds or tests the release after the push. Treat moving `vMAJOR` as a production deploy.

Rules that hold for the whole release:
- Never delete, move, or force-push a `vX.Y.Z` tag. The only tag that ever moves is the floating `vMAJOR`.
- Push and publish only after an AskUserQuestion confirmation in this run. Approval given earlier in the conversation doesn't count.
- Never push with `--tags`, since it would push stray local tags.

Requested bump: `$ARGUMENTS` (if empty, recommend one in step 3).

## 1. Gather state

Run these and keep the output. Don't make any changes yet.

```bash
git fetch origin --tags --force   # --force updates a local vMAJOR that moved on origin
git status --porcelain
git rev-parse --abbrev-ref HEAD
git rev-list --left-right --count origin/main...HEAD      # behind / ahead
LAST=$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*')
git log --oneline "$LAST"..HEAD
git diff --stat "$LAST"..HEAD
```

The `--match` pattern skips floating tags like `v1`, which point at the same commit as the latest release.

## 2. Gates: when NOT to release

Go through every gate.
- **STOP**: say why, suggest the fix, and end without creating a tag. Don't fix a STOP yourself unless the user asks.
- **CONFIRM**: explain the risk, then ask the user with AskUserQuestion before going on.

**Repository state: STOP if any of these fail**
- The fetch failed. Every check below would use stale tags.
- The current branch isn't `main`.
- The working tree has uncommitted or untracked changes. A tag records a commit, so local edits won't ship, and that's misleading.
- `HEAD` is ahead of `origin/main`. Unpushed commits would go out in a tag no one reviewed on main, and they haven't been through CI. Ask the user to push main first and wait for CI.
- `HEAD` is behind `origin/main`. You'd be tagging a stale commit.
- The target tag already exists, locally or on `origin` (`git ls-remote --tags origin vX.Y.Z`). Choose the next version.

**Nothing to ship: STOP**
- There are no commits since `$LAST`.
- `action.yml` hasn't changed since `$LAST`:
  ```bash
  git diff --quiet "$LAST"..HEAD -- action.yml
  ```
  If that exits 0, only the README, tests, CI config, or `.claude/` changed. Consumers run nothing but `action.yml`, so a new tag would ship the same action under a new number. Say that and stop.

**Verification: STOP if any of these fail**
- Lint, matching the `lint` job in `test.yml`. That job runs actionlint plus `test/shellcheck-action.sh`, which excludes SC2129 and SC2153:
  ```bash
  jactionlint --profile correctness --ignore 'SC2129|SC2153'
  ```
- CI on the exact commit. The integration tests run only on GitHub's six runners against the mock server, so this is the real test gate:
  ```bash
  gh run list --workflow test.yml --commit "$(git rev-parse HEAD)" --limit 1 --json status,conclusion,url
  ```
  STOP if it failed or is still running. If there's no run for this commit, or `gh` isn't available, treat it as a CONFIRM.

**Risky content: CONFIRM each one that applies**
- **Input compatibility.** Diff the inputs: `git diff "$LAST"..HEAD -- action.yml` and read the `inputs:` section. Each of these breaks every `@vMAJOR` workflow as soon as the tag moves, and needs a major bump:
  - an input was removed or renamed
  - an input's default changed
  - an input became `required: true`
  - an accepted value was removed

  List what changed and recommend a major release.
- **Uploader binary requirement.** Check whether the "Run TestNod uploader" step passes new flags to the binary: `git diff "$LAST"..HEAD -- action.yml | grep -E '^[-+].*ARGS'`.
  - The release that adds the flag must already be `latest`: `curl -fsSL https://releases.testnod.com/testnod-uploader/latest/VERSION`.
  - The minimum `uploader-version` must be stated in the input's description and in the README. With a pinned older binary, the step fails with "flag provided but not defined".
- **Server-side dependency.** If the change relies on a TestNod webapp change, ask whether that change is **deployed to production**. That covers the finalize request in `action.yml`, and request fields sent by a new binary flag.
- **Third-party actions.** If a `uses:` line in `action.yml` changed (for example `actions/cache`), it runs inside every consumer's job. Summarize the change and any runner requirement it adds, such as a newer Node version or runner version.

## 3. Choose the version

Tags are `vMAJOR.MINOR.PATCH` with no pre-release suffix. Recommend a bump from the commits since `$LAST`:
- **patch**: bug fixes and internal changes that don't change inputs or default behavior.
- **minor**: new inputs or new behavior that is off by default.
- **major**: any input compatibility break from step 2. Recommend it when one exists, but bump major only with the user's explicit agreement. A major release creates a new floating tag (`v2`) and leaves `v1` where it is. Before tagging, the README's `@v1` examples must say `@v2`. STOP if they don't.

If `$ARGUMENTS` is an explicit `vX.Y.Z`, check that it's valid semver and strictly greater than `$LAST`. If it isn't, STOP.

## 4. Summarize and confirm

Show the user one summary:
- `$LAST` → new version, the commit SHA to be tagged, and which floating tag moves (or is created)
- The commits included, one line each
- The result of every gate, with any CONFIRM items called out
- Draft release notes. They become the GitHub Release body in step 7. Keep them short and user-facing:
  - Lead with new or changed inputs and anything a workflow author has to change.
  - State any minimum `uploader-version`.
  - Say compatibility breaks plainly.
  - Group test and CI-only changes under "Maintenance", or leave them out.
  - Describe doc changes only as "documentation updates".
  - List only what changed. Never add a bullet saying that inputs, defaults, or usage are unchanged.
  - Don't include examples ("for example", "such as", "e.g.", or a parenthetical case) unless the user explicitly asks for one. State the change itself.

Then ask with AskUserQuestion:
- **Release** (push `vX.Y.Z` and move `vMAJOR`)
- **Push vX.Y.Z only** (don't move `vMAJOR`; only workflows that pin `@vX.Y.Z` get it)
- **Create tag locally only**
- **Cancel**

## 5. Tag and push

Version tags are signed and annotated, with the version as the message:
```bash
git tag -s vX.Y.Z -m vX.Y.Z
git tag -v vX.Y.Z
```
If signing fails (for example, no pinentry in a non-interactive shell), don't fall back to an unsigned tag. Give the user the command to run themselves: `! git tag -s vX.Y.Z -m vX.Y.Z`. For **Create tag locally only**, stop here and give the user the step 5 commands still to run.

Push the version tag:
```bash
git push origin vX.Y.Z
```

Only for **Release**, point the floating tag at the release commit. Use `^{commit}` so `vMAJOR` points at the commit rather than wrapping the `vX.Y.Z` tag object:
```bash
git tag -s -f vMAJOR -m vMAJOR 'vX.Y.Z^{commit}'
git push --force origin refs/tags/vMAJOR
```
`--force` is allowed only here, on the floating major tag. For a new major, the tag doesn't exist yet, so drop both `-f` and `--force`.

## 6. After pushing

- Check that both tags on `origin` peel to the commit you tagged: `git ls-remote --tags origin vX.Y.Z vMAJOR` (compare the `^{}` lines).
- Tell the user that every `@vMAJOR` workflow picks up the release on its next run, and hand verification back to them. A quick check is a workflow that uses `@vMAJOR`.
- Rollback: if the release breaks consumers, the fast fix is to move `vMAJOR` back to `$LAST^{commit}` the same way as in step 5. Ask before doing it. Then fix forward with a new patch release, never by moving `vX.Y.Z`.

## 7. GitHub Release

Skip this step if the tag was only created locally.

This step needs `gh`, installed and authenticated (`gh auth status`). Without it, give the user the release notes and the command from step 7.4, then stop.

1. Read the current latest release as the template: `gh release view --json tagName,name,body`. Match its format:
   - The title is the bare version (`vX.Y.Z`).
   - The body starts with `## What's new` and a one-line summary.
   - Then come `###` sections of short bullets.
2. Draft the notes in that format from the step 4 draft, following the same rules (user-facing only, compatibility breaks stated plainly, doc changes only as "documentation updates", no "unchanged" bullets, no examples unless asked). Write them to a file in the scratchpad, not the repo.
3. Show the notes and ask with AskUserQuestion: **Publish release** / **Edit notes** / **Skip**. A GitHub Release is public, so ask even though the tag push was already approved.
4. Create and publish it:
   ```bash
   gh release create vX.Y.Z --verify-tag --title vX.Y.Z --notes-file <notes.md> --latest
   gh release list --limit 3
   ```
   Confirm `vX.Y.Z` shows as `Latest`, and link the release URL in the final report.
5. `gh` can't publish a release to GitHub Marketplace. If the action is listed there, tell the user to open the release in the web UI, tick **Publish this Action to the GitHub Marketplace**, and save.
