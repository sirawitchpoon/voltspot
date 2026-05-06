# `.github/` — repository CI configuration

GitHub Actions workflows that run on every PR and every push to `main`.
The free tier covers everything we run today (~5 minutes per build,
mostly under macOS minutes — billable on macOS once we exceed 2,000
free minutes/month, very unlikely at solo-dev pace).

## Workflows

| File | Trigger | Purpose |
|---|---|---|
| `workflows/ios.yml` | every PR + every push to `main` | `xcodebuild` health check on macos-15. No code signing — verifies sources still compile. |
| `workflows/scripts.yml` | PRs + pushes that touch `scripts/**` | Node 20 syntax check + `seed-stations.js --dry-run`. Cheap, fast — only runs when scripts change. |
| `workflows/go.yml` | PRs + pushes that touch `backend/ocpp-gateway/**` | `go build`, `go vet`, `go test -race`. Verifies tidy state of `go.mod` so dependency drift doesn't sneak in. |

## What's NOT here yet (deferred)

- **Tests** — there's no test target wired into the Xcode project. When `VoltspotTests/*.swift` finally lands as a target, add `xcodebuild test` to `ios.yml`.
- **Linting** — no SwiftLint config. Add as a separate step (`brew install swiftlint && swiftlint --strict`) if linting policy is added.
- **Auto-deploy** — Firestore rules + Cloud Run images deploy *manually* during Phase B build-out. Once stable, add `firebase deploy --only firestore:rules` on `main` push, gated to `deploy/**` paths.
- **Branch protection** — enable via GitHub UI: Settings → Branches → Add rule for `main` → require status checks (iOS Build, Scripts) to pass before merge.

## Adding a new workflow

1. Drop `workflows/<name>.yml` next to the existing files.
2. Use `concurrency.group` so multi-push to the same branch cancels in-flight runs.
3. Document the workflow in the table above and explain *why* it's worth its CI minutes.

## Secrets handling

No secrets in CI today — `GoogleService-Info.plist` is stubbed in `ios.yml` because the build doesn't *use* it (FirebaseApp reads at runtime). When CI starts deploying:
- **Firebase service account** → upload as a base64-encoded GitHub Actions secret (`FIREBASE_SERVICE_ACCOUNT_BASE64`), `echo $FIREBASE_SERVICE_ACCOUNT_BASE64 | base64 -d > sa.json` in the deploy step.
- **GCP credentials** → use `google-github-actions/auth` with Workload Identity Federation, **not** a long-lived JSON key.
- Never echo secrets to the workflow log.
