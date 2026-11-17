# CLAUDE.md

Conventions for every repository of the `iretail-pro` organization. This copy
in `docs` is the master; each repository carries the same text plus a
repository-specific **Project** and **Status** section. **Read it first.**

## Communication

| Rule | Detail |
|---|---|
| Detect | My Language from context. |
| Speak | All chat, explanations, status updates, questions — in **My Language**. |
| Code | All identifiers, comments, commit messages, log strings, error messages, docs and Git branch names are **American English**. American spelling: `color`, `organize`, `behavior`, `canceled`. |
| UI strings | English is the default locale (`en`), Russian the second (`ru`); every string lives in ARB from day one and must fit with 30 % extra length. |
| Clarifying questions | Ask in My Language, but code in your proposal stays English. |

### Never state anything unverified

Not a style preference — a hard rule.

| Rule | Detail |
|---|---|
| Check, then say | Every claim about the state of the world — a branch, a PR, a file's contents, a passing test, a working device — is made **after** running the command that shows it, never from memory or inference. |
| Show the evidence | State the command's actual output, not a summary of what it probably said. |
| Read your own output | A check whose result you narrate without reading is worse than no check. |
| Say "I don't know" | Unverified is a legitimate answer. Inventing a plausible one destroys the value of everything else reported. |
| Separate done from believed | "Tests pass" only after they ran. "Fixed" only after it was observed fixed. Anything that could not be checked here — a fiscal printer, a real payment terminal, a phone — is called out as unverified in the same breath as the claim. |

## Product

**iRetail PRO** — a self-hosted retail platform for shops and chains of any
profile on an international market: a register (POS), a store back office, a
network hub with a console and dashboards, a white-label customer app, a
device gateway for scanners, scales, fiscal and receipt printers and card
terminals, an in-app assistant on the chain's own model keys, and an MCP
server for external agents. The product plan is
[`docs/plans/0001-product-plan.md`](docs/plans/0001-product-plan.md).

Repositories (see the plan's "Репозитории и что настроить"): `docs` (this),
`contracts`, `core`, `data-exchange-node`, `device-gateway`, `cashier`,
`manager`, `customer-app`, `modules`, `design`, `deploy`, `site`, `brands`.
Data import (CSV, XLSX, Google Sheets) lives in `data-exchange-node`; there
is no per-system migrator. Sibling projects with the same conventions, used
as references and never edited from here: Tabellum (`dudko-dev/tabellum`) and
Baton (`dudko-dev/baton`).

## Stack (do not change without asking)

| Area | Choice |
|---|---|
| Apps | Flutter 3.x / Dart 3.x, Riverpod; one codebase for Windows, Linux, macOS, iOS, Android and the browser. No BLoC, no GetX. |
| Servers | Rust (tokio, axum, sqlx, tonic): one `node` binary in two roles, `store` and `hub`; stateless, horizontally scalable. |
| Device drivers | Go: the device gateway only (gRPC, plugins; scanners over HID/USB-COM/Bluetooth, scales over Mettler 8217/SASI/NCI, printers over ESC/POS and StarPRNT, labels over ZPL, Stripe Terminal through its server-driven REST API, an EBT-capable path through Datacap). Nothing else is Go. |
| Data | PostgreSQL 17 everywhere; SQLite inside the register app as cache and receipt queue only; Redis for holds, locks and pub/sub; Kafka in the hub from the first release; Qdrant with `BAAI/bge-m3` embeddings (local ONNX by default, any OpenAI-compatible endpoint on the chain's key; NFC-normalized text, token-based truncation) for semantic search and tags; analytics marts in PostgreSQL for a store and a small hub, ClickHouse for a chain hub, one query contract. |
| Contracts | protobuf/gRPC, OpenAPI, GraphQL SDL and conformance fixtures in `contracts`, generated for Dart, Rust and Go. Contracts are written before code. |
| Deployment | From the first release: Docker Compose for a store and a small hub; Helm for the hub in Kubernetes; Terraform/Terragrunt for AWS, GCP and self-hosted; built-in userspace WireGuard (keys and profiles issued by the hub, off by default, never touching the device's system VPN). No cloud of ours. Minimum OS: nothing older than five years at release (Windows 10 21H2 / 11, macOS 12+, Ubuntu 22.04 / Debian 12+, iOS 16+, Android 12+). |
| Licensing | Offline Ed25519 keys per organization carrying tier, modules, stores, registers and term. |
| Forbidden | Electron, React Native, per-platform native UI rewrites; ORMs in the server; a proxy of ours in front of model providers; telemetry without asking; business logic in Go. |

## Architecture invariants

Break them only after explicit discussion and an ADR.

| # | Invariant | Why |
|---|---|---|
| 1 | **Servers are stateless.** `node` keeps nothing between requests; state lives in PostgreSQL, Redis (holds and locks with TTL) and Kafka. Any replica serves any request. | Scaling and rolling updates without code changes. |
| 2 | **Contracts first, one domain, four doors.** REST, GraphQL, WebSocket and MCP are generated from one domain layer and one permission layer; the same conformance fixtures hold Dart and Rust in agreement. | "Works in the app, fails over the API" is unacceptable. |
| 3 | **Money is integers in the currency's minor unit; quantities are in the base unit to 0.001.** Currency and unit system are properties of the store; conversion happens only in hub reports at the rate of the day. No floats. | Two implementations must produce the same cents. |
| 4 | **Stock changes only through documents.** Available = on hand − hard holds. A hard hold is created by a register line and lives in Redis with a TTL; a customer cart is a soft hold that blocks nothing and only notifies. | Two registers never sell the last unit; the shop floor is never blocked by an app cart. |
| 5 | **Offline is a state, not an error.** A store works without the hub indefinitely; a register works without the node until the end of the shift; everything is replayed through outbox/inbox with idempotency keys. | Retail does not stop for the network. |
| 6 | **Agents propose, people approve.** Every write initiated by the assistant or an MCP client is shown in the UI and confirmed by a person with the right role. Row-level data goes to a model provider only with an explicit organization setting. | The hub is trusted with the chain's data. |
| 7 | **Secrets never enter files, logs or model context.** Provider keys, device tokens, WireGuard private keys and payment credentials live in OS secure storage or the cluster's secret store. | A leaked repository or log must not leak a store. |
| 8 | **Modules are feature flags of one build.** A disabled module hides its screens and answers `module_disabled`; nothing is downloaded or built per customer. | One image, one key, one support path. |
| 9 | **License verification is offline.** Ed25519 against an embedded public key; a grace period keeps the register selling. | Air-gapped stores exist. |

## Code style

Dart: Effective Dart, `dart format`, `flutter_lints`; `async/await`; immutable
models; sealed error hierarchies; no `dynamic` outside the JSON boundary; one
non-trivial type per file. Rust: `rustfmt` + `clippy` clean; `thiserror`
errors with stable codes across the API; no `unwrap` outside tests. Go:
`gofmt`, `go vet`, `staticcheck`; typed sentinel errors; context cancellation
everywhere. TypeScript (site): `strict`, ESM, ESLint + Prettier. Every new
dependency needs a one-line justification in the PR.

Naming: `UpperCamelCase` types, `lowerCamelCase` functions and variables in
Dart and TS, Go per Effective Go, Rust per the API guidelines; booleans
`is…/has…/should…`; no Hungarian notation, no type suffixes.

Logging: structured; never log card data, secrets, personal data of
customers, or full receipts of stores marked sensitive.

## UI work

Every screen is designed with the `ux-design` skill and the design system in
`docs/design/`, and verified at 1440 × 900 and 390 × 844 in both themes, plus
1024 × 768 for the register and 390 × 508 (soft keyboard) for any screen with
a field, before it counts as done (`screen-check` skill). Previews go to the
user without being asked (`preview` skill). Interfaces are not clones of
existing registers: start from the task and the keystroke count, not from a
template.

## Commits and PRs

Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
`chore:`) with scopes `node`, `cashier`, `manager`, `gateway`, `contracts`,
`core`, `deploy`, `docs`, `design`, `site`. Subject ≤ 72 characters,
imperative, no period. One logical change per commit; one milestone — one PR
(smaller is fine), merged into `main` when `pr-checks` is green. Never commit
`.env`, secret values, real license keys, device credentials, build artifacts
or compiled binaries. CI publishes, signs or deploys only on
`workflow_dispatch`; `pr-checks` runs on pull requests. Every job runs on
`${{ fromJSON(vars.RUNNER) }}`: GitHub-hosted `ubuntu-latest` for now (the
owner's call, 2026-10-18), a self-hosted runner later by changing the
organization variable, never by editing workflows.

## Documentation workflow

| Directory | Contents | Skill |
|---|---|---|
| `docs/plans/` | Plans and roadmaps, `NNNN-slug.md` | `plan` |
| `docs/issues/` | Bugs, tasks, open questions, `NNNN-slug.md` | `issue` |
| `docs/adr/` | Architecture decision records, `NNNN-slug.md` | `adr` |
| `docs/design/` | Design system, logo, mockups, screenshots | `ux-design`, `preview` |
| `docs/research/` | Market and technology research with dated, source-marked figures | — |

Decisions go to ADRs, never silently; questions go to issues; each milestone
gets its own plan whose checklist is ticked in the same PR as the code.

## Things NOT to do

- ❌ Don't put anything from a real customer's systems in a repository: no real
  chain names, hosts, IPs, products, prices or people. Invent (`Corner
  Market`, `192.0.2.x`).
- ❌ Don't execute an assistant- or MCP-originated write without the approval
  gate, not even for a test.
- ❌ Don't store money as floating point or convert currencies outside hub
  reports.
- ❌ Don't add a cloud service of ours between a customer and their data or
  their model provider.
- ❌ Don't ship a module as a separate build or image.
- ❌ Don't hardcode `runs-on`; every job uses `${{ fromJSON(vars.RUNNER) }}`.
  Keep CI artifacts small and `retention-days: 1`: hosted minutes and
  artifact storage are organization-wide quotas.
- ❌ Don't hand-edit generated code (`*.g.dart`, `*.freezed.dart`, generated
  clients from `contracts`).

## When in doubt — ask

Before changing an invariant or the stack, adding a dependency, touching
secrets, licensing, payments or the approval gate, or spending more than
~30 minutes without progress: stop and ask in My Language.

## Status

2026-10-18 — product plan written (`docs/plans/0001-product-plan.md`) and
revised with the owner's decisions: first market USA (country pack `us`),
pilots supermarket / pharmacy / grocery / coffee shop / pizzeria, Kafka and
ClickHouse from the first release, Helm and Terraform for AWS, GCP and
self-hosted at once, built-in WireGuard, bge-m3 embeddings, universal import
instead of a migrator, minimum OS not older than five years. Research in
`docs/research/` (US hardware shortlist, US pricing); the pricing grid is
approved by the owner (2026-10-18). Design system and five mockups in
`docs/design/`, `ux-design` skill added. **M0 is done**
(`docs/plans/0002-m0-foundation.md`): contracts with a reference checker,
`core` (Dart) and the node's domain crate (Rust) passing the same fixtures,
device emulators, design tokens, the dev compose with demo stores and a
privacy audit. **M1 is done** (`docs/plans/0003-m1-store-node.md`): the
store role of `node` on PostgreSQL 17 and Redis 7 (auth and RBAC, catalog,
FIFO/FEFO stock through documents, holds, shifts, receipts, outbox events,
audit, license; REST and GraphQL checked against `contracts`), the store
compose file, the `iretail-node` Helm chart and Terraform modules for AWS,
GCP and self-hosted. **M2 is done** (`docs/plans/0004-m2-device-gateway.md`):
the Go `gateway` serves the device service over gRPC with drivers for
ESC/POS and ZPL printers, 8217 and NCI ECR scales, serial scanners and Stripe
Terminal, each tested against an emulator. **M3 is done**
(`docs/plans/0005-m3-register.md`): the Flutter register sells against the
node and the gateway — cash, card, EBT and split tenders through the
gateway's terminal, weighed goods from a live scale under NTEP's rules,
returns and voids refunded to the card, senior approvals at the value the
node names, age checks from an ID's PDF417, promotions computed alike by the
node and the register, items with options, order types, tips and kitchen
tickets (ADR-0015 to ADR-0017) — and keeps selling without the node from its
own SQLite copy with a PIN verifier and a receipt queue replayed with
idempotency keys (ADR-0018); a simplified mode, an upright tablet layout,
and measurements in the sandbox (cashier README, "Performance"). `core` and
`iretail_design` reach apps as vendored copies at pinned commits
(ADR-0014). **M4 is done** (`docs/plans/0006-m4-back-office.md`): the
Flutter back office `manager` runs a store from its node — the catalog,
groups, taxes, staff and roles, stock with lots and expiry, receiving,
write-off, price change and inventory documents counted from several
devices at once, blind (ADR-0020), promotions, the sales report, CSV and
XLSX written by the node, PDF forms and price tags written by the app with
no dependency, shelf labels through the gateway (ADR-0021), and the import
of a CSV, Excel file or Google Sheet through sessions on the node
(ADR-0019). **M5 is done** (`docs/plans/0007-m5-hub.md`): the hub
role and sync are done (M5a, M5b) — the hub's API, a journal written with
every record that crosses, ownership with change requests, and one gRPC
exchange per store under mutual TLS from an authority the registration
token pins (ADR-0022), checked by a hub and a store node on one machine;
the chain log goes to Kafka (M5c), and the analytics marts are fed by it in
PostgreSQL or ClickHouse under one query layer over the metrics catalog
(M5d, ADR-0023); the back office is the hub's console (M5e): dashboards
as YAML over that query layer with drills, stores and nodes with their sync
state and registration tokens, change requests, the chain's prices per
store, and the same app in a browser behind its own nginx on the hub's
origin (ADR-0024); agents reach every node through one tool layer (M5f,
ADR-0025): MCP over Streamable HTTP and the assistant on the chain's own
model key, whose writes are proposals a person approves in the back office,
with masking, stubs instead of old rows, compaction and a call log with
cost; search by meaning and tags run in the node on Qdrant with `bge-m3`
embedded or a chain's endpoint (M5g, ADR-0026): the catalog searches by
meaning, the node suggests tags and groups a person accepts, the register
adds similar items under its exact search; the license's limits hold in a
chain (M5h, ADR-0027): the hub shares the key's registers out store by
store, each store enforces its share offline, the console shows what is
spent, and `assistant`, `search` and `analytics` are the modules that gate;
the chain's health and backups are watched from the hub (M5h, ADR-0028):
Prometheus metrics and OTLP traces on every node, each store's health on
the exchange, six alert rules at the hub with webhook notices, encrypted
logical archives from every node kept by the hub in the organization's
bucket, and the hub's WAL archived with pgBackRest for recovery to a
moment; and the chain can run inside its own private network (M5h,
ADR-0029): userspace WireGuard inside the node (boringtun under smoltcp, no
interface, no root), the hub the center for the stores and each store's
node for its devices, `/24` blocks of the organization's subnet, the
exchange inside the tunnel with no fallback, the switch and the stores'
tunnels in the console; a device's own tunnel in the apps is issue 0042.
**M6 is done** (`docs/plans/0008-m6-us-pack.md`): the `us` pack — sales
tax as codes by jurisdiction that tax item categories, with holidays, set
per store by the hub and never shipped with rates (ADR-0030); SNAP shedding
the tax on what it pays for, with the node's dry run the figure after an
approval, and state container deposits (ADR-0031); the pseudoephedrine
logbook kept only in the store, its limits checked by the node, never sold
offline (ADR-0032); FSA and HSA amounts sent to the terminal as IIAS, not to
Stripe (ADR-0033); the kitchen display as a mode of the register on its own
device token, worked by a bump bar (ADR-0034); e-receipts through the
organization's own mail server and SMS provider (ADR-0035); store profiles
setting the apps' defaults, the tax report, the back office's editors and
an invented demo store per pilot profile. The rates themselves are the
owner's question (issue 0001); WIC (0046), NPLEx (0044), taking empties
back (0043) and the tax in the healthcare amount (0045) are open.
**M7 is done** (`docs/plans/0009-m7-payments-hardware.md`): Adyen,
Clover, Worldpay and Fiserv as server-driven terminal drivers beside
Stripe (ADR-0036), Star CloudPRNT and Epson Server Direct Print printers
polling the gateway (ADR-0037), tax rates from the organization's Avalara
or TaxJar account into the codes a mapping names (ADR-0038), variants as
items and serials per unit (ADR-0039), and the hub's reports converted
between currencies at the rate of each day (ADR-0040) — in the node, the
register (the variant grid, a serial per unit, returns by serial, what the
terminal can do) and the back office (the variant matrix, serials on
receiving and write-off, the tax service card, exchange rates and a
currency picker on dashboards). The second country pack waits for its
client (issue 0048), label scales through ePLUM and Data GateWeigh for
their specifications (0049); two approvals in one receipt is issue 0052.
**M8 is done** (`docs/plans/0010-m8-world-foundation.md`): the audit
log is a hash chain written under one lock and anchored at the hub and on
the Z report (ADR-0041); fiscalization is a list of back ends a register
composes, with the gateway's fiscal registrar behind `emulator_fiscal` and
no real registrar's driver written from guesses — the VM8119's waits for
its manufacturer's description, issue 0050 (ADR-0042); GS1 codes fill the
sale line and an expired unit needs a senior's approval (ADR-0043);
several cashiers sell on one register's shift, each with an X (ADR-0044);
the receipt and the Z print tax lines; eight more languages (de, es, fr,
pl, hy, ky, kk, pt-BR) ship machine-translated until native review, issue
0051, with Noto Sans Armenian after Inter (ADR-0045) — in the node, the
register and the back office; the `observability` profile runs
Prometheus, the OpenTelemetry Collector, Tempo and Grafana with the node's
dashboards (deploy); the research on fiscal rules in 45 countries is in
`docs/research/fiscal-requirements.md`; the cashier's, back office's,
administrator's and hardware guides are Typst sources in `docs/manuals/`
with figures rendered by the apps. What building M8 found is issues 0053
to 0056. **M9 is done** (`docs/plans/0011-m9-trade-loyalty.md`):
transfers between a chain's stores relayed by the hub, purchase orders
and supplier returns, re-grades, kits and production (ADR-0047), batch
prices and expiry rules run daily (ADR-0048), loyalty balances with one
owner, held and settled, in a fixed order of discounts (ADR-0049), gift
cards kept as keyed hashes with PINs behind a lockout (ADR-0050), stamp
cards, vouchers, partner codes and employee bonuses fixed at the sale
(ADR-0051) — in the node, the register, the back office and the
console's Reports — and the US pack made a country module a store is in
or not (ADR-0046); the rules for gift cards and customers' data wait for
the owner (issue 0057). The guides follow M9 and ADR-0046: the general
guides describe the base product, the Russian ones with figures shot in
an invented store in BYN with metric units and VAT in its prices, and the
US pack has a guide of its own (`docs/manuals/us-pack`, en and ru) that
the others point to. **M10 is done**
(`docs/plans/0012-m10-restaurant.md`): the floor plan drawn in the back
office, checks by table and tab with seats and courses held at the node
with their stock (ADR-0052), send, hold and fire to the kitchen, moving,
merging and moving lines, splitting by items, by seats or equally into
ordinary receipts that never divide a line (ADR-0053), the pre-bill, the
stop list, offline closing with check conflicts for a person, and the
guest menu served by the store's node on a guest listener of its own with
a QR code on every table, its orders confirmed by staff (ADR-0054) — in
the node, the register (and its handheld layout and kitchen display), the
back office, the deployment (an overlay in compose, its own Service and
Ingress in the chart, proxy examples) and the guides; the guest page
checked in Chromium on the demo pizzeria, not on a phone. The restaurant
is a priced license module, `restaurant`, free up to three tables (the
owner's decision of 2026-10-21, issue 0068, ADR-0057): without it a store
has three places, and tables past the first three are locked for new
checks, never for a check under way. Under the owner's delegation
(2026-10-21) a service charge is a line of the receipt inside its total,
never a tip — up to three percent charges per store, by party size and
order type, taxed by the store's codes or as each line is, with the
staff's part reported as wages (ADR-0058, issue 0069) — and a check's
kitchen ticket says table or tab, the floor carries the waiter's name and
the store sets when a table is seated long (issue 0071); both are in
contracts#46 and go in before 1.0 (plan 0013, M11h). The hub's bonus and
partner totals are per currency now (0070) and an orphaned hold is
released with `loyalty.manage` alone (0065). **M11 is in progress** (`docs/plans/0013-m11-release-1-0.md`): releases
with signed manifests rolled out by the hub in waves, self-updating apps,
the product site with plans, a TCO calculator and keys, the full manuals,
1.0; ADR-0055 and ADR-0056 accepted; the restaurant module costs $19 per
store, free up to three tables, inside the Café and Pro bundles; keys are
sold by invoice and bank transfer, a card through Paddle optional
(ADR-0071, which supersedes ADR-0059; issue 0072), and
installers signed with Microsoft Artifact Signing and Apple's
notarization (ADR-0060), while opening the accounts, buying the
certificates and generating the keys stay the owner's (issue 0073);
a full code and security review and a full retest with the UI come before
the tags (M11i). 2026-10-25: M11j (safe updates end to end, ADR-0062) and
ADR-0064 (an old app refused per request, never by its version) are merged
in every repository; M11i's review and retest ran and their fixes are
merged (issues 0074 and 0075); the five guides and the 1.0.0 release notes
describe M11i, M11j and ADR-0064, every figure shot again from cashier
6907b25 and manager be83157. 2026-10-26: the release checklist is
`docs/releases/1.0.0/checklist.md`. The owner made the release keys and
the license key; both release keys' public halves are embedded and every
part is 1.0.0 (core#39, data-exchange-node#37, device-gateway#15, site#10,
deploy#26, cashier#31, manager#33); the guides no longer say there is no
release key. The Windows installers are not signed for 1.0, the macOS ones
are signed and notarized once their secrets are set (deploy#27,
`signed_installers`). The 1.0 tags wait for the secrets still unset (the
checklist's section 1, issue 0073) and for GitHub's minutes (2026-11-01).
**M12 (white label) is done in code** (`docs/plans/0014-m12-white-label.md`,
ADR-0065 to ADR-0070): a chain's own look is data, a brand and a store's
banner held to the design system's contrast pairs and served to the apps by
the node under the `white_label` module; customers reach a public API on a
listener of its own (sign-in by a one-time code, a card shown as a QR code of
a token good for 15 minutes, a storefront with levels and never numbers, a
cart that holds nothing, preorders that hold their store's stock, online
payment through the chain's own Stripe account, authorized at the order and
captured at hand-over); pushes go from the hub with the chain's own keys; the
customer app (Flutter, white label, with a short help) and the register on
phones and handhelds (DataWedge and camera scanning, the price and expiry
check, receiving, counting, price changes with shelf tags, preorder picking
and hand-over) are built per chain from `brands/` by `tool/brand.sh` and the
`brand-release` workflows, their icons resized in Dart with nothing installed
on the runner; the back office has the brand editor, the customer app's
settings, promotion pushes, the store's public profile and preorders; the
cashier's, administrator's and back office's guides describe them. Not run
anywhere: Stripe, APNs, FCM, a phone or a Zebra, Gradle, Xcode, the brand
workflows (issue 0081); the customer app registers no phone for pushes yet
(issue 0077); Tap to Pay waits for Apple's entitlement; the chain's store
accounts are the owner's (G3). What M12 found is issues 0077 to 0082.
ADR-0001 to ADR-0071 and issues 0001 to 0082 in `docs`; issue 0026 (offline sales below the book stock),
issue 0033 (a record a receiver cannot apply), issue 0037 (masking a date
with a spaced time) and issue 0041 (what the price list's other modules
turn off) wait for the owner. No real model provider was called here.
Not verified
here: the chart on a real cluster, any cloud apply, any real device or
payment account, the apps on Windows or macOS or on a store PC (the Linux
desktop release builds here), a real label printer, the private network
across two machines or NAT, a real mail server or SMS provider, a real FSA
card or IIAS processor, a real ID scanner or bump bar, any real fiscal
registrar, a real 2D scanner reading GS1 codes, a native speaker's reading
of the new languages. Shared contracts are copied into consumers
pinned by commit (`CONTRACTS_REF`, ADR-0002); CI runs once per ready pull
request (ADR-0004). This section is copied into a repository with its next
change, so an older copy may lag. The session's GitHub App cannot create
organization repositories (403), so `scripts/bootstrap-github.sh` creates
and configures them with `gh` from the owner's account; it is idempotent and
`DRY_RUN=1` prints the calls. Branch protection on private repositories
needs GitHub Team; on the Free plan the script warns and goes on. CI runs on
GitHub-hosted runners for now (`vars.RUNNER` = `"ubuntu-latest"`); no
self-hosted runner and no CI secrets until a workflow needs them.

## This repository

iRetail PRO software: builds, signs and publishes a release from the source
repositories (public, while the sources are private). One workflow,
`.github/workflows/release.yml` (README, "Releasing"): the apps for Linux,
Windows and macOS, the register for Android and iOS, the gateway, the node's,
updater's and console's images, the deployment kit, a manifest signed with
the release key, a GitHub Release `v<version>`, and the images on ghcr.io;
only what users download, nothing of the site. The master copy of the shared
part of this file lives in `iretail-pro/docs`; change it there and copy it
here.

Checks: `actionlint` (with shellcheck) on the workflows and `shellcheck
scripts/*.sh` (pr-checks). A release cannot be run without the owner's
secrets; never dispatch one (a real version publishes for good).

**Status** (2026-11-14, the first workflow; the owner's decisions: this
repository public, the release built here, Android and iOS too, the images
published from here). Not run yet: it needs `IRETAIL_SOURCES_TOKEN` and the
release key in the environment `release`.

**Status** (2026-11-17, the demo image; README, "The demo"): `demo/` and
**demo** (`.github/workflows/demo.yml`) build `ghcr.io/iretail-pro/software/demo`
for a published release: the seven pilot stores of deploy's `demo/pilots`
in one container, each its own node, database and port (8081 to 8087) with
the back office and the register in the browser, the gateway with emulated
devices on 50051, a start page on 8080. Verified here on Docker 29 with
1.0.0, linux/amd64: `scripts/demo-context.sh` (the manifest checked with
release-1, the node and console pulled by its digests), the image built,
`scripts/demo-test.sh` (7 of 7 stores, each signing in with both tokens and
listing its items), the back office and the register paired in Chromium
and a cash sale made in the browser register, `DEMO_STORES` and a stop in
1 s. Not run: the workflow on GitHub, the linux/arm64 node build and the
arm64 image, Docker Desktop on macOS or Windows, the desktop register
against the gateway in the container.

