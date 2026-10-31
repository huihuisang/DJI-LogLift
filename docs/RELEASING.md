# Tag releases

Push a version tag to build a signed, notarized universal DMG and create a GitHub preview release:

```sh
jj tag set v0.1.1 -r master
jj git push --remote origin --tag v0.1.1
```

Use the intended version number. Do not reuse or move a published tag. Tags must use `vMAJOR.MINOR.PATCH`, with an optional suffix such as `-rc.1`. The tagged commit must be reachable from `origin/master`. The tag sets the app version; the workflow run number sets its build number. No version file is rewritten.

Ordinary `master` pushes and pull requests run Checks without signing secrets. Release runs the same checks before importing credentials. The package job has read-only repository permissions. Only the publication job has `contents: write`, and it receives no signing credentials.

All automated releases are previews until clean-system acceptance is complete. A hosted build and command-line assessment do not establish a quarantine-aware download, offline installation, or first launch on a clean Mac. Run that acceptance separately before promoting a release for production use.

## Repository settings

Actions secrets:

- `DEVELOPER_ID_P12_BASE64`: encrypted PKCS#12 certificate and private key, encoded as base64.
- `DEVELOPER_ID_P12_PASSWORD`: its password.
- `ASC_PRIVATE_KEY_BASE64`: App Store Connect API private key, encoded as base64.
- `ASC_KEY_ID` and `ASC_ISSUER_ID`: API key identifiers.

Actions variables:

- `DEVELOPER_ID_SHA1`: exact Developer ID Application certificate fingerprint.
- `APPLE_TEAM_ID`: expected signing team.

Use `gh secret set` with stdin. Never put a secret in source, command arguments, issues, screenshots, or logs. The workflow imports the certificate into a temporary keychain, grants codesign access only in that keychain, and removes the keychain and decoded secrets on exit. Credentials are outside every artifact upload path.

## Release gates and recovery

Checks also requires a clean worktree after XcodeGen and verification, so the committed project must match the tested project. The package script verifies signatures, Team ID, secure timestamps, Hardened Runtime, sandbox entitlements, arm64/x86_64, bundled resources and license notices. It signs a read-only DMG, saves the notarization submission ID immediately, waits on that ID, reads the accepted log, staples the DMG, verifies Gatekeeper, and checks the actual mounted app. Publication checks the local and live remote tag, source commit, receipt and final SHA-256 again. A missing remote tag is never recreated. Existing Releases are never overwritten. The published asset digest is checked against the verified receipt.

If notarization times out, download the release evidence artifact and query the saved submission ID. Do not submit the same pending file again. Failed jobs preserve evidence but do not publish a Release. A failure during GitHub upload can leave a draft; inspect it before recovery rather than deleting or replacing assets automatically.

For a complete packaging rehearsal, run **Actions → Release → Run workflow** on `master`. The supplied tag is a version label for that run. Manual runs produce verified Actions artifacts and evidence; they never publish a GitHub Release. This permits validation without inventing a public version tag or changing an existing release.

The runner is `macos-26` with Xcode 26.6. Action versions are pinned to commit hashes. Update those pins and the toolchain deliberately, then rerun the packaging rehearsal.
