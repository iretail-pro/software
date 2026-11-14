# iRetail PRO software

Releases of iRetail PRO: the apps for every platform we ship, the device
gateway, the containers a store or a hub runs, and the deployment kit,
built here from the source repositories and signed with the release key.

Download from [Releases](https://github.com/iretail-pro/software/releases).
Each release `v<version>` carries:

| File | What |
|---|---|
| `cashier-<version>-linux-x64.tar.gz`, `-windows-x64.zip`, `-macos-universal.zip` | the register |
| `manager-<version>-…` | the back office (also served by a hub as its web console) |
| `cashier-<version>-android.apk` | the register on Android phones and handhelds (the iPhone build goes to TestFlight instead) |
| `gateway-<version>-linux-x64.tar.gz`, `-linux-arm64.tar.gz`, `-windows-x64.zip`, `-macos-universal.tar.gz` | the device gateway |
| `node-…`, `updater-…`, `console-<version>-linux-x64.oci.tar` | the images, also on `ghcr.io/iretail-pro/software/node`, `software/updater`, `software/console` |
| `iretail-deploy-<version>.tar.gz` | the deployment kit: compose files, Helm chart, Terraform, install scripts |
| `manifest.json` | the signed manifest: every file above but the phone builds, with its SHA-256 and size |
| `iretail-<version>.tar` | the air-gapped bundle for `node release import` at a hub |
| `SHA256SUMS`, `version.json`, `notes-en.md`, `notes-ru.md` | |

A store, a hub and the apps check `manifest.json` against the release keys
they embed (contracts `spec/RELEASES.md`); the phone builds are outside the
manifest and checked by `SHA256SUMS`. The software needs a license key to
run beyond Starter (one store, one register): iretail.pro.

## Releasing

By hand only: Actions, **release**, Run workflow, on `main`, with the
version. Every source repository must already carry that version
(`Cargo.toml`, `pubspec.yaml`, `VERSION`); the plan job refuses otherwise,
and refuses a version released already. The run fixes the source commits
once (shown in its summary), builds everything on GitHub's hosted runners,
assembles the manifest with no secret in reach, signs it in the environment
`release`, verifies it with openssl and `iretail-release`, then pushes the
images by digest and creates the GitHub Release. Only what users download
is here: nothing is published to the site. Nothing is pushed or published before the
manifest is signed.

## Secrets

Repository secrets unless noted. Each signing set is all or nothing: with
none of it the run builds that part unsigned (desktop) or skips it (phones)
and says so; with part of it the run fails.

| Name | For |
|---|---|
| `IRETAIL_SOURCES_TOKEN` | a fine-grained token with Contents: read on the organization's repositories (data-exchange-node, cashier, manager, device-gateway, deploy, docs) |
| `IRETAIL_RELEASE_KEY` | **in the environment `release`** (add required reviewers there): the release key's seed |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | Developer ID signing and notarization of the macOS apps |
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | Windows signing (Artifact Signing) |
| `ANDROID_KEYSTORE` (base64), `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | the Android APK |
| `IOS_CERTIFICATE_P12` (base64, Apple Distribution), `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE` (base64, App Store, bundle id `pro.iretail.iretailCashier`), `IOS_TEAM_ID` | the register for iPhone, uploaded to TestFlight after publish with the `APPLE_API_*` key; the app's record must exist in App Store Connect |

Variables: `IRETAIL_LICENSE_PUBLIC_KEY` (the license issuer's public key,
compiled into the node), `IRETAIL_RELEASE_KEY_ID` (`release-1`),
`IRETAIL_RELEASE_PUBLIC_KEYS` (`[{"key_id": "release-1", "public_key":
"<64 hex>"}, …]`), and for Windows signing `ARTIFACT_SIGNING_ENDPOINT`,
`ARTIFACT_SIGNING_ACCOUNT`, `ARTIFACT_SIGNING_PROFILE`.

## Images

The images are this repository's own packages:
`ghcr.io/iretail-pro/software/node`, `software/updater` and
`software/console`, tagged `<version>` and pushed by the digests the
manifest names. The first release creates them; then, once, set each
package's visibility to **Public** (its Package settings). The manifest
names these repositories, so a store's updater pulls them from here.

## Runners

The jobs run on the variables `RUNNER`, `RUNNER_WINDOWS`, `RUNNER_MACOS` (a
`runs-on` value as JSON), GitHub's hosted runners when unset; for a public
repository those cost no minutes, macOS included. Set this repository's own
variable `RUNNER` to `"ubuntu-latest"`: the organization's self-hosted
runner must never serve a public repository, whose pull requests anyone can
open.

## What deploy's release still does

Release gates 1 to 3 (contracts `spec/RELEASES.md`, "Release gates") and a
rotation release's two runs are in deploy's `release.yml`, not here yet.

## Not verified

Nothing here has run on GitHub: the first run needs the secrets above. The
assemble, sign and verify steps were run locally on real gateway archives
and a deployment kit with a TEST ONLY key; the image, desktop, Android and
iOS jobs were not (no Docker, Flutter desktop targets, Android SDK or Xcode
in the session that wrote them).
