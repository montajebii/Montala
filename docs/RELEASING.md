# Releasing Montala

This project uses [Semantic Versioning](https://semver.org/) for the public
version and Flutter's build number as the Android `versionCode`.

## Version policy

`pubspec.yaml` is the single source of truth:

```yaml
version: 1.2.0+3
│       │   │
│       │   └── build number → Android versionCode (must always increase)
│       └────── patch / minor / major
└────────────── versionName shown to users
```

- **MAJOR** — a change users must adapt to (removed tools, data format break,
  dropped platform, incompatible import/export change).
- **MINOR** — new tools, new screens, new settings, meaningful new behaviour.
- **PATCH** — fixes and polish with no new surface area.
- **Build number (`+N`)** — increments for *every* build sent to a store, even
  if the version name is unchanged. Google Play rejects a reused `versionCode`;
  APKs split per ABI get `1000 × ABI` added by Flutter on top of this number.
- A released version name is never reused. If a shipped build is broken, ship
  `1.2.1+4`, not another `1.2.0+4`. Tags are never moved or deleted.
- Every release has an annotated tag `vX.Y.Z` whose version equals `pubspec.yaml`.
  `python3 tools/release.py check --tag vX.Y.Z` enforces this in CI.

Git tags already in use: `v1.0.0`, `v1.0.1`, `v1.2.0`, `v1.2.1`. This release: `v1.2.2` (`1.2.2+5`).
Version `1.1.0` was developed but never published, so the next public
version after `v1.0.1` was `v1.2.0`.

## Application identifiers

| Platform | Identifier |
|---|---|
| Android `applicationId` / `namespace` | `ir.m0nt.montala` |
| Android Kotlin package | `ir.m0nt.montala` |
| Linux GApplication id / `StartupWMClass` | `ir.m0nt.montala` |

The application id is part of the product identity, not just a build detail.
Changing it creates a separate installation with no access to the previous
app's private data, and a store will treat it as a new listing. Never change it
after the first upload; ship under the existing id instead.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/). While
working, add user-visible bullets under `## [Unreleased]` in the matching
`### Added / Changed / Fixed / Build` section. Entries are written in English,
in the past tense, and describe observable behaviour — not refactors, not commits.

Before a release, generate a starting point from commit subjects:

```bash
python3 tools/release.py draft --since v1.2.1   # prints a draft, never edits
```

Review every line against the actual diff. If something is not in the changelog,
it must not change user-facing behaviour. The release gate fails when the
`Unreleased` section is empty or `CHANGELOG.md` has no dated section matching
the current version.

## Android signing

Release artefacts are signed with the upload key. Google Play App Signing uses
this as the upload key and re-signs with Google's app-signing key.

Local setup (already done on this machine):

| Item | Location |
|---|---|
| Keystore | `~/.config/montala/android-upload.jks` (4096-bit RSA, 10,000 days) |
| Credentials | `~/.config/montala/android-upload-credentials.txt` (mode 600) |
| Gradle config | `android/key.properties` (gitignored, mode 600) |
| Alias | `upload` |
| Certificate SHA-256 | `5B:E2:81:11:80:B9:38:0D:A0:12:F8:8A:92:CA:25:12:0C:DA:28:5D:9D:ED:D4:F8:6A:D3:62:0C:9C:18:4E:73` |

**Back up the keystore and the credentials file now** — password manager plus an
offline copy, for example. Never commit either file. Losing the upload key does
not lose the app on Play (the app-signing key stays with Google), but it
requires an upload-key reset through Play support; losing it before any upload
just means generating a new key.

`android/app/build.gradle.kts` uses the release signing config when
`android/key.properties` exists and falls back to the debug key otherwise
(with a warning). `tools/build_all.sh` refuses to package Android artefacts
unless the release key is present, unless `--allow-debug-signing` is passed for
a local test build.

### CI secrets

The release workflow signs with the same upload key. Add these repository
secrets (`Settings → Secrets and variables → Actions`):

```bash
base64 -w0 ~/.config/montala/android-upload.jks   # → ANDROID_KEYSTORE_BASE64
```

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the `.jks` above (single line) |
| `ANDROID_KEYSTORE_PASSWORD` | store password from the credentials file |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password from the credentials file |
| `ANDROID_CERT_SHA256` | optional expected certificate digest (the fingerprint above) |

The CI job verifies the built APK and AAB are signed and, when
`ANDROID_CERT_SHA256` is set, that the certificate matches.

## Release procedure

```bash
# 1. Development: keep CHANGELOG.md's Unreleased section current.
#    At release time, sanity-check the draft:
python3 tools/release.py draft --since v1.2.1

# 2. Promote Unreleased, bump pubspec + app version, run analyze/tests,
#    commit and tag (annotated). This is the release commit.
python3 tools/release.py prepare --version 1.2.2

# 3. Build every local artefact (signed AAB + APKs, web zip, Linux bundle +
#    AppImage) and write dist/SHA256SUMS.
./tools/build_all.sh --no-sync --no-pub

# 4. Publish: the v* tag triggers CI, which re-verifies the version and
#    changelog, builds every platform (including Windows) and creates the
#    GitHub release with notes extracted from CHANGELOG.md.
git push origin main --follow-tags
```

`tools/build_all.sh` without flags also refreshes the bundled datasets and runs
`flutter pub get`; the flags above are for offline machines with a warm pub cache.
Artifacts:

```
dist/Montala-<v>-web.zip
dist/Montala-<v>-linux-x64.tar.gz
dist/Montala-<v>-x86_64.AppImage
dist/android/Montala-<v>.aab            ← Google Play upload
dist/android/Montala-<v>-<abi>.apk      ← direct install / non-Play stores
dist/SHA256SUMS
```

The AAB is the file to give Google Play. Direct-download stores and the GitHub
release use the signed APKs (all three ABIs are built).

## Store upload checklist

- [ ] `python3 tools/release.py check --tag vX.Y.Z` passes.
- [ ] `versionCode` is greater than the last upload.
- [ ] Artifacts in `dist/` are freshly built from the tagged commit.
- [ ] AAB signed with `CN=Montala` (upload key), not the debug key.
- [ ] `CHANGELOG.md` matches what is actually in the build.
- [ ] Keystore + credentials backed up.
- [ ] Test the release on a clean device/browser, including data import.

## Emergency rebuild of an already-tagged release

Tags are immutable. Fix forward: add the fix, bump `PATCH` (and always the build
number), write a changelog entry, tag and release again. If the broken tag was
never published, delete it locally/remotely *and* bump the version anyway so no
two different binaries can ever share a version name.
