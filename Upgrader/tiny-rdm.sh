#!/usr/bin/env bash
# Upgrader/tiny-rdm.sh
# 用途：自动获取 tiny-rdm 最新 release（或使用传入版本），下载 macOS dmg，计算 sha256，
# 并更新仓库中的 Casks/tiny-rdm.rb 中的 version 与 sha256（arm/intel）。
#
# 用法：
#   ./Upgrader/tiny-rdm.sh               # 获取 upstream 最新 release 并更新本地 Cask 文件（不会自动提交）
#   ./Upgrader/tiny-rdm.sh 1.2.5         # 指定版本号（可以带或不带前缀 v）
#   ./Upgrader/tiny-rdm.sh --commit      # 执行更新并创建本地分支、提交并打印 push/PR 指令
#   ./Upgrader/tiny-rdm.sh --commit --push  # 还会把分支 push 到 origin
#
# 依赖：curl, jq, perl, shasum 或 sha256sum, git (如使用 --commit)
set -euo pipefail

REPO_OWNER="tiny-craft"
REPO_NAME="tiny-rdm"
CASK_PATH="Casks/tiny-rdm.rb"

COMMIT=0
PUSH=0
VERSION=""

usage() {
  cat <<EOF
Usage: $0 [version] [--commit] [--push]
  --commit   create branch and commit changes locally (branch name: update/tiny-rdm-VERSION-TIMESTAMP)
  --push     push the created branch to origin (only valid with --commit)
If version omitted, will fetch latest release from upstream.
EOF
}

# parse args
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

# Determine helper for sha256
if command -v shasum >/dev/null 2>&1; then
  SHASUM_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHASUM_CMD="sha256sum"
else
  echo "Require shasum or sha256sum in PATH" >&2
  exit 1
fi

# get latest tag if version not provided
if [[ -z "$VERSION" ]]; then
  echo "Fetching latest release tag from upstream..."
  api="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to parse JSON. Please install jq." >&2
    exit 1
  fi
  TAG="$(curl -sL "${api}" | jq -r .tag_name)"
  if [[ -z "$TAG" || "$TAG" == "null" ]]; then
    echo "Failed to fetch latest tag" >&2
    exit 1
  fi
  # strip leading v if present
  VERSION="${TAG#v}"
  echo "Latest upstream version: ${VERSION} (tag ${TAG})"
fi

TAG="v${VERSION}"
BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG}"
INTEL_NAME="TinyRDM_${VERSION}_mac_intel.dmg"
ARM_NAME="TinyRDM_${VERSION}_mac_arm64.dmg"
INTEL_URL="${BASE_URL}/${INTEL_NAME}"
ARM_URL="${BASE_URL}/${ARM_NAME}"

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

echo "Downloading dmg files to ${TMPDIR}..."
set -x
curl -fL -o "${TMPDIR}/${INTEL_NAME}" "${INTEL_URL}"
curl -fL -o "${TMPDIR}/${ARM_NAME}" "${ARM_URL}"
set +x

echo "Computing sha256 sums..."
INTEL_SHA="$($SHASUM_CMD "${TMPDIR}/${INTEL_NAME}" | awk '{print $1}')"
ARM_SHA="$($SHASUM_CMD "${TMPDIR}/${ARM_NAME}" | awk '{print $1}')"
echo "intel: ${INTEL_SHA}"
echo "arm  : ${ARM_SHA}"

if [[ ! -f "${CASK_PATH}" ]]; then
  echo "Cask file not found at ${CASK_PATH}" >&2
  exit 1
fi

echo "Backing up current Cask to ${CASK_PATH}.bak"
cp "${CASK_PATH}" "${CASK_PATH}.bak"

echo "Updating version in ${CASK_PATH}..."
perl -0777 -pe "s/version\\s+\"[^\"]+\"/version \"${VERSION}\"/s" -i "${CASK_PATH}"

echo "Updating sha256 block in ${CASK_PATH}..."
# If the cask currently uses :no_check, replace it. Otherwise replace arm/intel block.
if grep -qE 'sha256\s+:no_check' "${CASK_PATH}"; then
  perl -0777 -pe "s/sha256\\s+:no_check/sha256 arm:   \"${ARM_SHA}\",\\n         intel: \"${INTEL_SHA}\"/s" -i "${CASK_PATH}"
else
  # try to replace existing arm/intel block; if not matched, insert after version line
  if perl -0777 -ne 'print if /sha256\s+arm:/s' "${CASK_PATH}" >/dev/null 2>&1; then
    perl -0777 -pe "s/sha256\\s+arm:\\s+\"[^\"]+\",\\s*intel:\\s+\"[^\"]+\"/sha256 arm:   \"${ARM_SHA}\",\\n         intel: \"${INTEL_SHA}\"/s" -i "${CASK_PATH}"
  else
    # insert sha256 block after version line
    perl -0777 -pe "s/(version\\s+\"${VERSION}\"\\s*\\n)/\$1  sha256 arm:   \"${ARM_SHA}\",\\n         intel: \"${INTEL_SHA}\"\\n/s" -i "${CASK_PATH}"
  fi
fi

echo "Updated ${CASK_PATH} — please review changes: git diff -- ${CASK_PATH}"
if [[ $COMMIT -eq 1 ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not inside a git repository — cannot commit automatically." >&2
    exit 1
  fi
  BRANCH="update/tiny-rdm-${VERSION}-$(date +%s)"
  git checkout -b "${BRANCH}"
  git add "${CASK_PATH}"
  git commit -m "tiny-rdm: update to ${VERSION} (update sha256)"
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