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
| `cashier-<version>-android.apk`, `manager-<version>-android.apk`, `customer-<version>-android.apk` | the register, the back office and the customer app on Android; the customer app is the example chain, Corner Market (a chain's own build comes from `brands/`). The iPhone builds of the three go to TestFlight instead |
| `gateway-<version>-linux-x64.tar.gz`, `-linux-arm64.tar.gz`, `-windows-x64.zip`, `-macos-universal.tar.gz` | the device gateway |
| `node-…`, `updater-…`, `console-<version>-linux-x64.oci.tar` | the images, also on `ghcr.io/iretail-pro/software/node`, `software/updater`, `software/console` |
| `guide-admin-<version>-en.pdf`, `-ru.pdf` | the administrator's guide: installing and running a store's server or a hub (the containers), the gateway, pairing, backups, updates |
| `guide-cashier-…`, `guide-manager-…`, `guide-hardware-…`, `guide-us-pack-…` (`en`, `ru`) | the register's, the back office's and console's, the devices' and the US pack's guides |
| `iretail-deploy-<version>.tar.gz` | the deployment kit: compose files, Helm chart, Terraform, install scripts |
| `manifest.json` | the signed manifest: every file above but the phone builds, with its SHA-256 and size |
| `iretail-<version>.tar` | the air-gapped bundle for `node release import` at a hub |
| `SHA256SUMS`, `version.json`, `notes-en.md`, `notes-ru.md` | |

The guides are built by each release from docs' `docs/manuals` at the
release's commit, their figures taken by the register's and the back
office's screen tests at theirs, so a guide always shows the version it
ships with. They are outside the signed manifest and checked by
`SHA256SUMS`.

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
is here: nothing is uploaded to the site, which reads a release from this
repository's GitHub release itself (site's README, "Releases and guides in
R2"). Nothing is pushed or published before the manifest is signed.

The run names the commits it builds from in `sources.txt`, a release asset
(one `<repository> <commit>` a line: the seven checked out, contracts as
the node copies it, core and design as the apps vendor them), and once the
release is published it tags each of them `v<version>`
(`scripts/tag-sources.sh`): a commit `main` does not hold is refused, a
tag already on that commit is left, a tag on another commit is never
moved. For a release published before this step existed (1.0.0), or when
the step failed, run **tag-sources** by hand with the version, and for a
release without `sources.txt` the list as the input `sources`.

## Secrets

Repository secrets unless noted. Each signing set is all or nothing: with
none of it the run builds that part unsigned (desktop) or skips it (phones)
and says so; with part of it the run fails.

| Name | For |
|---|---|
| `IRETAIL_SOURCES_TOKEN` | a fine-grained token with Contents: **read and write** on the organization's repositories data-exchange-node, cashier, manager, customer-app, device-gateway, deploy, docs, contracts, core and design: read to build, write only to tag each one `v<version>` once the release is published |
| `IRETAIL_RELEASE_KEY` | **in the environment `release`** (add required reviewers there): the release key's seed |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGN_IDENTITY`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | Developer ID signing and notarization of the macOS apps |
| `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` | Windows signing (Artifact Signing) |
| `ANDROID_KEYSTORE` (base64), `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | the three Android APKs, one upload key |
| `IOS_CERTIFICATE_P12` (base64, Apple Distribution), `IOS_CERTIFICATE_PASSWORD`, `IOS_TEAM_ID` | iPhone builds, uploaded to TestFlight after publish with the `APPLE_API_*` key |
| `IOS_PROFILE_CASHIER`, `IOS_PROFILE_MANAGER`, `IOS_PROFILE_CUSTOMER` (base64, App Store profiles for `pro.iretail.iretailCashier`, `pro.iretail.iretailManager`, `pro.iretail.customer`) | one per app; an app without its profile is skipped. Each app's record must exist in App Store Connect |

Variables: `IRETAIL_LICENSE_PUBLIC_KEY` (the license issuer's public key,
compiled into the node), `IRETAIL_RELEASE_KEY_ID` (`release-1`),
`IRETAIL_RELEASE_PUBLIC_KEYS` (`[{"key_id": "release-1", "public_key":
"<64 hex>"}, …]`), and for Windows signing `ARTIFACT_SIGNING_ENDPOINT`,
`ARTIFACT_SIGNING_ACCOUNT`, `ARTIFACT_SIGNING_PROFILE`.

## Images

The images are this repository's own packages:
`ghcr.io/iretail-pro/software/node`, `software/updater` and
`software/console`, tagged `<version>` and pushed by the digests the
manifest names. Once the release is published (not a prerelease), the tag
`latest` is set on the same digests (`scripts/tag-latest.sh`), which
deploy's compose files read by default. For a release published before
that step existed (1.0.0), or to point `latest` back at an earlier
release, run **tag-latest** by hand with the version: it reads the
release's manifest and moves only the tag. The first release creates them; then, once, set each
package's visibility to **Public** (its Package settings). The manifest
names these repositories, so a store's updater pulls them from here.

## The demo

Every pilot store of deploy's `demo/pilots` in one container, to try the
software on one computer with one command (Docker Desktop on macOS or
Windows, Docker on Linux; Intel and ARM):

```bash
docker run --rm -p 127.0.0.1:8080-8088:8080-8088 -p 127.0.0.1:50051:50051 ghcr.io/iretail-pro/software/demo
```

Then open <http://localhost:8080>: it lists the seven stores (supermarket,
pharmacy, grocery, coffee shop, pizzeria with its tables and guest menu,
apparel with variants, electronics with serial numbers), each on its own
port from 8081 to 8087 with the back office at `/` and the register at
`/register/` in the browser, its server address and device tokens for the
desktop apps of the release, and the sign-in (login `admin`, PIN
`246810`, or `-e DEMO_PIN=…`). `-e DEMO_STORES=pizzeria,grocery` starts only
those. The register in the browser has no device gateway, so it sells for
cash only; the desktop register pairs with the gateway on
`localhost:50051` (token `iretail-demo`), which drives emulated printers,
a scale, a scanner and card terminals, shown on the start page's devices
panel. The pizzeria's guest menu answers on 8088. Every store runs as
Starter (no license key): one register each, and the pizzeria seats its
first three tables. Nothing is kept: the stores are made again from the
pilots each time it starts. Keep the ports on `127.0.0.1` as above: the
start page shows the demo's tokens.

Inside: PostgreSQL 17 and Redis 7, one store node per pilot (its own
database and Redis database), the gateway and its emulators, and nginx
serving each store's browser apps with its API on the same origin
(`demo/`). **demo**, run by hand with a published version, builds it: the
node and the back office's browser build come from the release's own
images, pulled by the digests its signed manifest names (linux/amd64); the
node for linux/arm64 is built from data-exchange-node at `v<version>` with
the same Dockerfile and license key; the register's browser build, the
gateway and the pilots come from their repositories at `v<version>`
(`scripts/demo-context.sh`). It starts the image and checks every store
before it pushes `demo:<version>` and `demo:latest`
(`scripts/demo-test.sh`); set the package `software/demo` **Public** once,
as the others.

## Runners

The jobs run on the variables `RUNNER`, `RUNNER_WINDOWS`, `RUNNER_MACOS` and
`RUNNER_ARM` (the demo's linux/arm64 node, `ubuntu-24.04-arm` when unset; a
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
