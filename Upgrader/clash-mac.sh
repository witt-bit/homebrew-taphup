#!/usr/bin/env bash
# Upgrader script for clash-mac cask — aligned with tiny-rdm.sh CLI
# Usage: ./Upgrader/clash-mac.sh [version] [--commit] [--push]
# Requirements: git, curl, jq, shasum (or sha256sum/openssl), mktemp, perl
set -euo pipefail

REPO_OWNER="666OS"
REPO_NAME="ClashMac"
CASK_PATH="Casks/clash-mac.rb"

COMMIT=0
PUSH=0
VERSION=""

usage() {
  cat <<EOF
Usage: $0 [version] [--commit] [--push]
  --commit   create branch and commit changes locally (branch name: update/clash-mac-VERSION-TIMESTAMP)
  --push     push the created branch to origin (only valid with --commit)
If version omitted, will fetch latest release from upstream.
EOF
}

# parse args (positional version optional)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --commit)
      COMMIT=1
      shift
      ;;
    --push)
      PUSH=1
      shift
      ;;
    --* )
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -z "$VERSION" ]]; then
        VERSION="$1"
        shift
      else
        echo "Too many arguments" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }

if ! command_exists curl || ! command_exists jq || ! command_exists perl; then
  echo "Required command missing: curl, jq, perl are required." >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  SHASUM_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHASUM_CMD="sha256sum"
elif command -v openssl >/dev/null 2>&1; then
  SHASUM_CMD="openssl dgst -sha256"
else
  echo "Require shasum or sha256sum or openssl in PATH" >&2
  exit 1
fi

# Use GITHUB_TOKEN if available to reduce rate limits
AUTH_HEADER=""
if [ -n "${GITHUB_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
fi

if [[ -z "$VERSION" ]]; then
  echo "Fetching latest release tag from upstream..."
  API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
else
  # accept both 'v1.2.3' and '1.2.3' inputs
  TAG="${VERSION}"
  TAG="${TAG#v}"
  API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/v${TAG}"
fi

if [ -n "$AUTH_HEADER" ]; then
  release_json=$(curl -sfL -H "$AUTH_HEADER" "$API")
else
  release_json=$(curl -sfL "$API")
fi

if [ -z "$release_json" ]; then
  echo "Failed to fetch release info from $API" >&2
  exit 1
fi

tag_name=$(printf '%s' "$release_json" | jq -r '.tag_name // empty')
if [ -z "$tag_name" ]; then
  echo "No tag_name found in release JSON:" >&2
  printf '%s\n' "$release_json" | jq -r '.message // .' >&2
  exit 1
fi
echo "Selected tag: $tag_name"

# Select preferred asset: dmg > zip > tar.gz > any mac-related asset > fallback any asset
asset_entry=$(printf '%s' "$release_json" | jq -r '
  .assets as $a |
  ($a[] | select(.name|test("(?i)\\.dmg$")) ) //
  ($a[] | select(.name|test("(?i)\\.zip$")) ) //
  ($a[] | select(.name|test("(?i)\\.tar\\.gz$")) ) //
  ($a[] | select(.name|test("(?i)darwin|mac|osx")) ) //
  ($a[] ) |
  {name: .name, url: .browser_download_url} |
  @base64' | head -n1)

if [ -z "$asset_entry" ]; then
  echo "No suitable release asset found for ${REPO_OWNER}/${REPO_NAME} release." >&2
  exit 1
fi

asset_name=$(printf '%s' "$asset_entry" | base64 --decode | jq -r '.name')
asset_url=$(printf '%s' "$asset_entry" | base64 --decode | jq -r '.url')

echo "Selected asset: $asset_name"
echo "Download URL: $asset_url"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

asset_path="$tmpdir/$asset_name"
echo "Downloading asset..."
if [ -n "$AUTH_HEADER" ]; then
  curl -fL -H "$AUTH_HEADER" -o "$asset_path" "$asset_url"
else
  curl -fL -o "$asset_path" "$asset_url"
fi

echo "Computing sha256..."
if [[ "$SHASUM_CMD" == "openssl dgst -sha256" ]]; then
  new_sha=$(openssl dgst -sha256 "$asset_path" | awk '{print $2}')
else
  new_sha=$($SHASUM_CMD "$asset_path" | awk '{print $1}')
fi

echo "sha256: $new_sha"

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask file not found at ${CASK_PATH}" >&2
  exit 1
fi

echo "Backing up current Cask to ${CASK_PATH}.bak"
cp "$CASK_PATH" "${CASK_PATH}.bak"

# Normalize version without leading v
normalized_version="${tag_name#v}"

echo "Updating version/url/sha in ${CASK_PATH}..."
perl -0777 -pe "s/version\\s+\"[^\"]+\"/version \"${normalized_version}\"/s" -i "${CASK_PATH}"

# Try to replace sha256 in several common forms, or insert after version line
if grep -qE 'sha256\s+:no_check' "${CASK_PATH}"; then
  perl -0777 -pe "s/sha256\\s+:no_check/sha256 \"${new_sha}\"/s" -i "${CASK_PATH}"
else
  # First, remove ALL sha256 lines (including duplicates) that appear after the version line
  # Then insert a single sha256 line after version
  perl -0777 -pe "s/(version\\s+\"${normalized_version}\"\\s*\\n)((?:\\s*sha256[^\\n]*\\n)*)/\$1  sha256 \"${new_sha}\"\\n/s" -i "${CASK_PATH}"
fi

echo "Updated ${CASK_PATH} — please review changes: git diff -- ${CASK_PATH}"

if [[ $COMMIT -eq 1 ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository — cannot commit automatically." >&2
    exit 1
  fi
  BRANCH="update/clash-mac-${normalized_version}-$(date +%s)"
  git checkout -b "${BRANCH}"
  git add "${CASK_PATH}"
  git commit -m "clash-mac: update to ${normalized_version} (update sha256)"
  echo "Committed on branch ${BRANCH}."
  if [[ $PUSH -eq 1 ]]; then
    git push -u origin "${BRANCH}"
    echo "Branch pushed to origin/${BRANCH}."
    echo "You can now create a PR from the pushed branch, or use: gh pr create"
  else
    echo "Run: git push origin ${BRANCH}   to push branch and create PR."
  fi
else
  echo "No commit requested. If you want to commit the changes, run with --commit."
fi

echo "Done."