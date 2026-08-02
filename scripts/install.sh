#!/usr/bin/env bash
# Installs the changestack CLI from GitHub release assets into the runner
# tool cache and puts it on PATH. Used by both the setup action and the
# root action.
#
# Env in:  CS_VERSION ("latest", "0.2.0" or "v0.2.0"), CS_OS, CS_ARCH
#          (blank = detect from the runner), GH_TOKEN (optional, for API
#          rate limits).
# Outputs: version, cached, path (via $GITHUB_OUTPUT).
set -euo pipefail

REPO="erikburt/changestack"

os="${CS_OS:-}"
if [[ -z "$os" ]]; then
  case "${RUNNER_OS:-$(uname -s)}" in
    Linux) os=linux ;;
    macOS | Darwin) os=darwin ;;
    *)
      echo "::error::unsupported OS '${RUNNER_OS:-unknown}': changestack ships linux and darwin binaries"
      exit 1
      ;;
  esac
fi

arch="${CS_ARCH:-}"
if [[ -z "$arch" ]]; then
  case "${RUNNER_ARCH:-$(uname -m)}" in
    X64 | x86_64 | amd64) arch=amd64 ;;
    ARM64 | aarch64 | arm64) arch=arm64 ;;
    *)
      echo "::error::unsupported architecture '${RUNNER_ARCH:-unknown}': changestack ships amd64 and arm64 binaries"
      exit 1
      ;;
  esac
fi

# Auth is only used against the API (rate limits); asset downloads are
# public and curl would drop the header on the cross-host redirect anyway.
api_auth=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  api_auth=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

version="${CS_VERSION:-latest}"
if [[ "$version" == "latest" ]]; then
  version="$(curl -fsSL --retry 3 "${api_auth[@]}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest" |
    sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$version" ]]; then
    echo "::error::could not resolve the latest changestack release"
    exit 1
  fi
fi
version="${version#v}"

# Tool cache layout compatible with @actions/tool-cache:
# <cache>/<tool>/<version>/<x64|arm64>/ plus a sibling .complete marker.
cache_arch="$arch"
if [[ "$arch" == "amd64" ]]; then
  cache_arch=x64
fi
tool_dir="${RUNNER_TOOL_CACHE}/changestack/${version}/${cache_arch}"
marker="${tool_dir}.complete"

cached=false
if [[ -x "${tool_dir}/changestack" && -f "$marker" ]]; then
  cached=true
  echo "Found changestack ${version} (${os}/${arch}) in the tool cache."
else
  archive="changestack_${version}_${os}_${arch}.tar.gz"
  base_url="https://github.com/${REPO}/releases/download/v${version}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  echo "Downloading ${archive}..."
  curl -fsSL --retry 3 -o "${tmp}/${archive}" "${base_url}/${archive}"
  curl -fsSL --retry 3 -o "${tmp}/checksums.txt" "${base_url}/checksums.txt"

  (
    cd "$tmp"
    grep " ${archive}\$" checksums.txt >expected.txt
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum --check expected.txt
    else
      shasum -a 256 --check expected.txt
    fi
  )

  mkdir -p "$tool_dir"
  tar -xzf "${tmp}/${archive}" -C "$tool_dir"
  touch "$marker"
  echo "Installed changestack ${version} (${os}/${arch}) into the tool cache."
fi

echo "$tool_dir" >>"$GITHUB_PATH"
{
  echo "version=${version}"
  echo "cached=${cached}"
  echo "path=${tool_dir}"
} >>"$GITHUB_OUTPUT"

"${tool_dir}/changestack" --version
