# changestack-action

GitHub Actions for [changestack](https://github.com/erikburt/changestack),
the changeset-based versioning tool for mixed-ecosystem monorepos.

Two actions live here:

- **`erikburt/changestack-action`** (root) — runs the whole flow: creates
  tags + GitHub Releases for merged version PRs, then opens/updates the
  version PR from pending changesets.
- **`erikburt/changestack-action/setup`** — just installs the CLI onto
  the runner `PATH` (tool-cache aware), for workflows that want to run
  `changestack` commands themselves.

## The flow action

```yaml
# .github/workflows/version.yml
name: Version
on:
  push:
    branches: [main]
concurrency:
  group: changestack-version
permissions:
  contents: write
  pull-requests: write
jobs:
  changesets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0          # release-pr reads history for attribution
      - uses: erikburt/changestack-action@v1
        id: changestack
```

Every push to main it runs `changestack release` (tags + GitHub Releases
for anything merged and pending) and then `changestack release-pr`
(upserts the version PR). Both halves are idempotent; use the `mode`
input (`release` / `release-pr`) to run only one.

### Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `version` | `latest` | changestack CLI version to use |
| `token` | `github.token` | Token with `contents: write` + `pull-requests: write` |
| `cwd` | `.` | Repository root to operate in |
| `dir` | | Changestack directory override (default `.changestack`) |
| `mode` | `auto` | `auto` (release, then release-pr), `release`, or `release-pr` |

### Outputs

| Output | Description |
|--------|-------------|
| `released` | `"true"` when any package was newly released or tagged |
| `releases` | JSON: `{released, prs, releases: [...], byStrategy: {...}}` |
| `pr-number` / `pr-url` | The open version PR, when one exists |

Each entry in `releases` carries `name`, `dir`, `version`, `tag`,
`aliases`, `strategy` (`npm`, `cargo`, `helm`, `go`, `generic`),
`githubRelease` and `status` (`released`, `tagged`, or `exists` for
idempotent reruns).

### Reacting to releases by package type

`byStrategy` groups the same entries by their ecosystem, so follow-up
steps can publish artifacts only for what actually released:

```yaml
      - name: Push released charts to ECR
        if: steps.changestack.outputs.released == 'true'
        env:
          CHARTS: ${{ toJSON(fromJSON(steps.changestack.outputs.releases).byStrategy.helm) }}
        run: |
          echo "$CHARTS" | jq -c '.[]? | select(.status != "exists")' | while read -r rel; do
            name="$(jq -r .name <<<"$rel")"
            version="$(jq -r .version <<<"$rel")"
            dir="$(jq -r .dir <<<"$rel")"
            helm package "$dir" --version "$version"
            helm push "${name}-${version}.tgz" "oci://${ECR_REGISTRY}/charts"
          done
```

Note: tags and releases are created with the workflow's token; when that
is the default `GITHUB_TOKEN`, they do **not** fire `on: push: tags:` or
`on: release:` workflows in the same repo. Chain artifact builds off this
action's outputs (same job or a `needs:` job / reusable workflow) instead.

## The setup action

```yaml
      - uses: erikburt/changestack-action/setup@v1
        with:
          version: latest       # or "0.2.0" / "v0.2.0"
      - run: changestack status --check
```

Installs the requested version into the runner tool cache
(`$RUNNER_TOOL_CACHE/changestack/<version>/<x64|arm64>`, shared with
@actions/tool-cache conventions), verifies the release checksum, and
prepends it to `PATH`. Linux and macOS runners, amd64 and arm64.
Outputs: `version` (resolved), `cached`, `path`.

## Versioning

This repo versions itself with changestack: releases are tagged
`vX.Y.Z` and a floating `v{major}` tag (`v1`) tracks the latest release
of that major, so `@v1` stays current.
