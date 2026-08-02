#!/usr/bin/env bash
# Runs the changestack flow: release anything merged and pending, then
# open/update the version PR from pending changesets.
#
# Env in:  CS_MODE (auto|release|release-pr), CS_CWD, CS_DIR,
#          GITHUB_TOKEN (required by the CLI's forge commands).
# Outputs: released, releases, pr-number, pr-url (via $GITHUB_OUTPUT).
set -euo pipefail

mode="${CS_MODE:-auto}"
case "$mode" in
  auto | release | release-pr) ;;
  *)
    echo "::error::invalid mode '${mode}' (expected auto, release or release-pr)"
    exit 1
    ;;
esac

cd "${CS_CWD:-.}"

args=()
if [[ -n "${CS_DIR:-}" ]]; then
  args+=(--dir "$CS_DIR")
fi

# release-pr commits on the release branch; make sure git has an identity.
if ! git config user.email >/dev/null; then
  git config user.email "github-actions[bot]@users.noreply.github.com"
fi
if ! git config user.name >/dev/null; then
  git config user.name "github-actions[bot]"
fi

write_outputs() {
  {
    echo "released=${released}"
    echo "pr-number=${pr_number}"
    echo "pr-url=${pr_url}"
    echo "releases<<CHANGESTACK_EOF"
    echo "$release_json"
    echo "CHANGESTACK_EOF"
  } >>"$GITHUB_OUTPUT"
}

release_json='{"released":false,"prs":[],"releases":[],"byStrategy":{}}'
released=false
pr_number=""
pr_url=""

if [[ "$mode" == "auto" || "$mode" == "release" ]]; then
  if ! release_json="$(changestack release --json "${args[@]}")"; then
    # Partial results still land in the outputs for failure handlers.
    echo "::error::changestack release failed"
    [[ -n "$release_json" ]] && released="$(jq -r '.released' <<<"$release_json")"
    write_outputs
    exit 1
  fi
  released="$(jq -r '.released' <<<"$release_json")"
fi

if [[ "$mode" == "auto" || "$mode" == "release-pr" ]]; then
  if ! pr_json="$(changestack release-pr --json "${args[@]}")"; then
    echo "::error::changestack release-pr failed"
    write_outputs
    exit 1
  fi
  pr_number="$(jq -r 'if .pr > 0 then .pr else empty end' <<<"$pr_json")"
  pr_url="$(jq -r '.url // empty' <<<"$pr_json")"
fi

write_outputs
