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
  if [ -n "$AUTH_HEADER" ]; then
    release_json=$(curl -sfL -H "$AUTH_HEADER" "$API")
  else
    release_json=$(curl -sfL "$API")
  fi
else
  # accept both 'v1.2.3' and '1.2.3' inputs — try v-prefixed tag first, then bare tag
  TAG="${VERSION}"
  TAG="${TAG#v}"
  API_V="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/v${TAG}"
  API_NO_V="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${TAG}"
  if [ -n "$AUTH_HEADER" ]; then
    release_json=$(curl -sfL -H "$AUTH_HEADER" "$API_V" || true)
    if [ -z "$release_json" ]; then
      release_json=$(curl -sfL -H "$AUTH_HEADER" "$API_NO_V" || true)
      API="$API_NO_V"
    else
      API="$API_V"
    fi
  else
    release_json=$(curl -sfL "$API_V" || true)
    if [ -z "$release_json" ]; then
      release_json=$(curl -sfL "$API_NO_V" || true)
      API="$API_NO_V"
    else
      API="$API_V"
    fi
  fi
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

# Normalize version without leading v (used to locate assets)
normalized_version="${tag_name#v}"

# Expect two architecture-specific assets named exactly as in the Cask
# e.g. ClashMac-<version>-macos-arm64.zip and ClashMac-<version>-macos-x86_64.zip
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

asset_arm_entry=$(printf '%s' "$release_json" | jq -r --arg name "ClashMac-${normalized_version}-macos-arm64.zip" '.assets[] | select(.name==$name) | {name:.name, url:.browser_download_url} | @base64')
asset_intel_entry=$(printf '%s' "$release_json" | jq -r --arg name "ClashMac-${normalized_version}-macos-x86_64.zip" '.assets[] | select(.name==$name) | {name:.name, url:.browser_download_url} | @base64')

if [ -z "$asset_arm_entry" ] || [ -z "$asset_intel_entry" ]; then
  echo "Expected both arm64 and x86_64 assets not found for ${REPO_OWNER}/${REPO_NAME} release ${normalized_version}." >&2
  exit 1
fi

asset_arm_name=$(printf '%s' "$asset_arm_entry" | base64 --decode | jq -r '.name')
asset_arm_url=$(printf '%s' "$asset_arm_entry" | base64 --decode | jq -r '.url')
asset_intel_name=$(printf '%s' "$asset_intel_entry" | base64 --decode | jq -r '.name')
asset_intel_url=$(printf '%s' "$asset_intel_entry" | base64 --decode | jq -r '.url')

echo "Selected assets: $asset_arm_name, $asset_intel_name"

asset_arm_path="$tmpdir/$asset_arm_name"
asset_intel_path="$tmpdir/$asset_intel_name"

echo "Downloading arm64 asset..."
if [ -n "$AUTH_HEADER" ]; then
  curl -fL -H "$AUTH_HEADER" -o "$asset_arm_path" "$asset_arm_url"
else
  curl -fL -o "$asset_arm_path" "$asset_arm_url"
fi

echo "Downloading x86_64 asset..."
if [ -n "$AUTH_HEADER" ]; then
  curl -fL -H "$AUTH_HEADER" -o "$asset_intel_path" "$asset_intel_url"
else
  curl -fL -o "$asset_intel_path" "$asset_intel_url"
fi

echo "Computing sha256 for arm64 and x86_64..."
if [[ "$SHASUM_CMD" == "openssl dgst -sha256" ]]; then
  new_sha_arm=$(openssl dgst -sha256 "$asset_arm_path" | awk '{print $2}')
  new_sha_intel=$(openssl dgst -sha256 "$asset_intel_path" | awk '{print $2}')
else
  new_sha_arm=$($SHASUM_CMD "$asset_arm_path" | awk '{print $1}')
  new_sha_intel=$($SHASUM_CMD "$asset_intel_path" | awk '{print $1}')
fi

echo "arm64 sha256: $new_sha_arm"
echo "x86_64 sha256: $new_sha_intel"

if [[ ! -f "$CASK_PATH" ]]; then
  echo "Cask file not found at ${CASK_PATH}" >&2
  exit 1
fi

echo "Backing up current Cask to ${CASK_PATH}.bak"
cp "$CASK_PATH" "${CASK_PATH}.bak"

# Normalize version without leading v
normalized_version="${tag_name#v}"

echo "Updating version/url/sha in ${CASK_PATH}..."
perl -0777 -pe "s/version\s+\"[^\"]+\"/version \"${normalized_version}\"/s" -i "${CASK_PATH}"

# Update per-architecture sha256 entries using sed range patterns
# For on_arm block: replace sha256 value between on_arm and end
sed -i '' "/on_arm/,/^end$/s/sha256 \"[^\"]*\"/sha256 \"${new_sha_arm}\"/" "${CASK_PATH}"
# For on_intel block: replace sha256 value between on_intel and end
sed -i '' "/on_intel/,/^end$/s/sha256 \"[^\"]*\"/sha256 \"${new_sha_intel}\"/" "${CASK_PATH}"

# Remove any top-level sha256 lines that appear before the first on_arm/on_intel block
tmpfile=$(mktemp)
awk 'BEGIN{seen=0} { if ($0 ~ /^[[:space:]]*on_(arm|intel)[[:space:]]+do/) seen=1; if (seen==0 && $0 ~ /^[[:space:]]*sha256[[:space:]]+/) next; print }' "${CASK_PATH}" > "$tmpfile" && mv "$tmpfile" "${CASK_PATH}"

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