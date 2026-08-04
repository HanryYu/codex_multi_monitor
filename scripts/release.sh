#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./scripts/release.sh <version> [options]

Examples:
  ./scripts/release.sh 0.7.7
  ./scripts/release.sh v0.7.7 --resume
  ./scripts/release.sh 0.7.7 --skip-homebrew

Options:
  --resume         Continue an existing tag/release after an interrupted run
  --dry-run        Run all preflight checks without pushing main or a tag
  --skip-checks    Skip Swift build and focused regression tests
  --skip-homebrew  Do not update the HanryYu/tap casks
  -h, --help       Show this help
EOF
}

VERSION=""
RESUME=false
DRY_RUN=false
SKIP_CHECKS=false
SKIP_HOMEBREW=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resume)
            RESUME=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-checks)
            SKIP_CHECKS=true
            ;;
        --skip-homebrew)
            SKIP_HOMEBREW=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -* )
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$VERSION" ]]; then
                echo "Only one version may be provided" >&2
                exit 2
            fi
            VERSION="${1#v}"
            ;;
    esac
    shift
done

if [[ -z "$VERSION" ]]; then
    usage >&2
    exit 2
fi
if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Version must use x.y.z format without leading zeroes: $VERSION" >&2
    exit 2
fi
if [[ "$RESUME" == true && "$DRY_RUN" == true ]]; then
    echo "--resume and --dry-run cannot be combined" >&2
    exit 2
fi

TAG="v$VERSION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/Downloads}"
WORKFLOW_NAME="${RELEASE_WORKFLOW_NAME:-Release}"
TAP_NAME="${HOMEBREW_TAP_NAME:-HanryYu/tap}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codexmonitor-release.XXXXXX")"
MOUNT_POINT="$TMP_ROOT/mount"
MOUNTED=false
TAP_SOURCE_REPO=""
TAP_WORK_REPO="$TMP_ROOT/homebrew-tap"
CASK_FILES=()

cleanup() {
    if [[ "$MOUNTED" == true ]]; then
        hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

semver_is_greater() {
    local candidate="$1"
    local baseline="$2"
    local candidate_major candidate_minor candidate_patch
    local baseline_major baseline_minor baseline_patch
    IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
    IFS=. read -r baseline_major baseline_minor baseline_patch <<< "$baseline"

    if (( candidate_major != baseline_major )); then
        (( candidate_major > baseline_major ))
    elif (( candidate_minor != baseline_minor )); then
        (( candidate_minor > baseline_minor ))
    else
        (( candidate_patch > baseline_patch ))
    fi
}

find_release_run() {
    gh run list \
        --workflow "$WORKFLOW_NAME" \
        --event push \
        --limit 50 \
        --json databaseId,headBranch,headSha \
        --jq ".[] | select(.headBranch == \"$TAG\" and .headSha == \"$TARGET_SHA\") | .databaseId" \
        | sed -n '1p'
}

preflight_homebrew() {
    if [[ "$SKIP_HOMEBREW" == true ]]; then
        return
    fi

    require_command brew
    require_command ruby
    TAP_SOURCE_REPO="${HOMEBREW_TAP_REPO:-$(brew --repo "$TAP_NAME")}"
    if [[ -z "$TAP_SOURCE_REPO" || ! -d "$TAP_SOURCE_REPO/.git" ]]; then
        echo "Homebrew tap repository is unavailable: $TAP_NAME" >&2
        exit 1
    fi

    local tap_remote_url
    tap_remote_url="$(git -C "$TAP_SOURCE_REPO" remote get-url origin)"
    git clone --quiet --branch main --single-branch "$tap_remote_url" "$TAP_WORK_REPO"
    git -C "$TAP_WORK_REPO" config user.name "${RELEASE_GIT_USER_NAME:-CodexMonitor Release Bot}"
    git -C "$TAP_WORK_REPO" config user.email "${RELEASE_GIT_USER_EMAIL:-release@codexmonitor.local}"

    CASK_FILES=(
        "$TAP_WORK_REPO/Casks/codex-multi-monitor.rb"
        "$TAP_WORK_REPO/Casks/codexmonitor.rb"
    )
    for cask_file in "${CASK_FILES[@]}"; do
        if [[ ! -f "$cask_file" ]]; then
            echo "Missing cask file: $cask_file" >&2
            exit 1
        fi
    done

    git -C "$TAP_WORK_REPO" diff --quiet
}

for command in git gh swift xcrun hdiutil codesign shasum plutil spctl; do
    require_command "$command"
done

cd "$PROJECT_DIR"

if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Release must run from main" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree must be clean before release" >&2
    git status --short >&2
    exit 1
fi
echo "==> Syncing main and tags"
git fetch origin main --tags
CURRENT_MAIN_SHA="$(git rev-parse HEAD)"
read -r ahead behind < <(git rev-list --left-right --count HEAD...origin/main)
LATEST_TAG="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | sed -n '1p')"
LATEST_VERSION="${LATEST_TAG#v}"
LOCAL_TAG_SHA="$(git rev-list -n 1 "$TAG" 2>/dev/null || true)"
REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/$TAG^{}" | awk '{print $1}')"
if [[ -z "$REMOTE_TAG_SHA" ]]; then
    REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
fi

TAG_NEEDS_PUSH=false
if [[ "$RESUME" == true ]]; then
    if [[ -z "$LOCAL_TAG_SHA" && -z "$REMOTE_TAG_SHA" ]]; then
        echo "--resume requires an existing local or remote tag: $TAG" >&2
        exit 1
    fi
    if [[ -n "$LOCAL_TAG_SHA" && -n "$REMOTE_TAG_SHA" && "$LOCAL_TAG_SHA" != "$REMOTE_TAG_SHA" ]]; then
        echo "Local and remote $TAG point to different commits" >&2
        exit 1
    fi
    TARGET_SHA="${REMOTE_TAG_SHA:-$LOCAL_TAG_SHA}"
    if [[ -z "$LOCAL_TAG_SHA" ]]; then
        git fetch origin "refs/tags/$TAG:refs/tags/$TAG"
        LOCAL_TAG_SHA="$(git rev-list -n 1 "$TAG")"
    fi
    if [[ "$LOCAL_TAG_SHA" != "$TARGET_SHA" ]]; then
        echo "Local $TAG does not resolve to the expected commit" >&2
        exit 1
    fi
    if [[ -z "$REMOTE_TAG_SHA" ]]; then
        TAG_NEEDS_PUSH=true
    fi
    TAG_RELEASE_NOTES_FIRST_LINE="$(git show "$TARGET_SHA:RELEASE_NOTES.md" | sed -n '1p')"
    if [[ "$TAG_RELEASE_NOTES_FIRST_LINE" != "# CodexMonitor $VERSION" ]]; then
        echo "$TAG release notes do not start with: # CodexMonitor $VERSION" >&2
        exit 1
    fi
else
    TARGET_SHA="$CURRENT_MAIN_SHA"
    if (( behind > 0 )); then
        echo "Local main is behind origin/main; update it before releasing" >&2
        exit 1
    fi
    if [[ -n "$LOCAL_TAG_SHA" || -n "$REMOTE_TAG_SHA" ]]; then
        echo "Tag already exists: $TAG (use --resume to continue it)" >&2
        exit 1
    fi
    if [[ -n "$LATEST_VERSION" ]] && ! semver_is_greater "$VERSION" "$LATEST_VERSION"; then
        echo "Version $VERSION must be greater than latest release $LATEST_VERSION" >&2
        exit 1
    fi
    if [[ "$(head -n 1 RELEASE_NOTES.md)" != "# CodexMonitor $VERSION" ]]; then
        echo "The first line of RELEASE_NOTES.md must be: # CodexMonitor $VERSION" >&2
        exit 1
    fi
fi

gh auth status >/dev/null
preflight_homebrew

if [[ "$SKIP_CHECKS" == false && "$RESUME" == false ]]; then
    echo "==> Running release checks"
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    TARGET_ARCH="$(uname -m)"
    swift build
    xcrun swiftc -parse-as-library \
        -sdk "$SDK_PATH" \
        -target "$TARGET_ARCH-apple-macosx15.0" \
        -module-cache-path "$TMP_ROOT/plan-module-cache" \
        Sources/CodexMonitor/Models/UsageResponse.swift \
        scripts/test_plan_display_name.swift \
        -o "$TMP_ROOT/plan-tests"
    "$TMP_ROOT/plan-tests"
    xcrun swiftc -parse-as-library \
        -sdk "$SDK_PATH" \
        -target "$TARGET_ARCH-apple-macosx15.0" \
        -module-cache-path "$TMP_ROOT/policy-module-cache" \
        Sources/CodexMonitor/Services/WeeklyQuotaActivationPolicy.swift \
        scripts/test_weekly_quota_activation_policy.swift \
        -o "$TMP_ROOT/policy-tests"
    "$TMP_ROOT/policy-tests"
    xcrun swiftc -parse-as-library \
        -sdk "$SDK_PATH" \
        -target "$TARGET_ARCH-apple-macosx15.0" \
        -module-cache-path "$TMP_ROOT/relative-time-module-cache" \
        Sources/CodexMonitor/Services/RelativeResetTime.swift \
        scripts/test_relative_reset_time.swift \
        -o "$TMP_ROOT/relative-time-tests"
    "$TMP_ROOT/relative-time-tests"
    xcrun swiftc -parse-as-library \
        -sdk "$SDK_PATH" \
        -target "$TARGET_ARCH-apple-macosx15.0" \
        -module-cache-path "$TMP_ROOT/reset-radar-module-cache" \
        Sources/CodexMonitor/Models/CodexResetModels.swift \
        scripts/test_codex_reset_decoding.swift \
        -o "$TMP_ROOT/reset-radar-tests"
    "$TMP_ROOT/reset-radar-tests"
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run passed for $TAG"
    if (( ahead > 0 )); then
        echo "Would push $ahead main commit(s) before tagging"
    fi
    echo "Would push $TAG, wait for $WORKFLOW_NAME, validate the official app, and sync Homebrew"
    exit 0
fi

if [[ "$RESUME" == false ]]; then
    if (( ahead > 0 )); then
        echo "==> Pushing main"
        git push origin main
    fi

    git fetch origin main
    if [[ "$(git rev-parse origin/main)" != "$TARGET_SHA" ]]; then
        echo "origin/main changed during release checks; rerun from the updated main" >&2
        exit 1
    fi

    echo "==> Creating and pushing $TAG"
    git tag -a "$TAG" -m "CodexMonitor $VERSION"
    git push origin "$TAG"
elif [[ "$TAG_NEEDS_PUSH" == true ]]; then
    echo "==> Pushing existing local tag $TAG"
    git push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Reusing existing GitHub Release"
else
    echo "==> Waiting for GitHub Actions run"
    RUN_ID=""
    for _ in {1..120}; do
        RUN_ID="$(find_release_run)"
        if [[ -n "$RUN_ID" ]]; then
            break
        fi
        sleep 5
    done
    if [[ -z "$RUN_ID" ]]; then
        echo "Could not find the $WORKFLOW_NAME run for $TAG and $TARGET_SHA" >&2
        echo "Resume later with: ./scripts/release.sh $VERSION --resume" >&2
        exit 1
    fi

    if [[ "$RESUME" == true ]]; then
        RUN_STATUS="$(gh run view "$RUN_ID" --json status --jq '.status')"
        RUN_CONCLUSION="$(gh run view "$RUN_ID" --json conclusion --jq '.conclusion // empty')"
        if [[ "$RUN_STATUS" == "completed" && "$RUN_CONCLUSION" != "success" ]]; then
            echo "==> Rerunning failed GitHub Actions run $RUN_ID"
            gh run rerun "$RUN_ID"
        fi
    fi
    gh run watch "$RUN_ID" --exit-status
fi

RELEASE_URL="$(gh release view "$TAG" --json url --jq '.url')"

echo "==> Downloading and validating the official DMG"
DMG_NAME="CodexMonitor-$VERSION.dmg"
DMG_PATH="$TMP_ROOT/$DMG_NAME"
gh release download "$TAG" --pattern "$DMG_NAME" --dir "$TMP_ROOT" --clobber
hdiutil verify "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
DMG_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=true
APP_PATH="$MOUNT_POINT/CodexMonitor.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "CodexMonitor.app is missing from the official DMG" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vv -t exec "$APP_PATH"
/usr/bin/lipo "$APP_PATH/Contents/MacOS/CodexMonitor" -verify_arch arm64 x86_64
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "Official app version mismatch: expected $VERSION, got $BUNDLE_VERSION" >&2
    exit 1
fi
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNTED=false

mkdir -p "$DOWNLOADS_DIR"
cp "$DMG_PATH" "$DOWNLOADS_DIR/$DMG_NAME"

if [[ "$SKIP_HOMEBREW" == false ]]; then
    echo "==> Updating Homebrew casks"
    for cask_file in "${CASK_FILES[@]}"; do
        ruby -pi -e "gsub(/^  version \"[^\"]+\"$/, '  version \"$VERSION\"'); gsub(/^  sha256 \"[^\"]+\"$/, '  sha256 \"$DMG_SHA\"')" "$cask_file"
        grep -Fqx "  version \"$VERSION\"" "$cask_file"
        grep -Fqx "  sha256 \"$DMG_SHA\"" "$cask_file"
    done

    (
        cd "$TAP_WORK_REPO"
        git diff --check
        ruby -c Casks/codex-multi-monitor.rb
        ruby -c Casks/codexmonitor.rb
        brew style Casks/codex-multi-monitor.rb Casks/codexmonitor.rb
        if ! git diff --quiet || ! git diff --cached --quiet; then
            git add Casks/codex-multi-monitor.rb Casks/codexmonitor.rb
            git commit -m "chore: update CodexMonitor to $VERSION"
        fi
        git push origin HEAD:main
        LOCAL_TAP_SHA="$(git rev-parse HEAD)"
        REMOTE_TAP_SHA="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
        if [[ "$LOCAL_TAP_SHA" != "$REMOTE_TAP_SHA" ]]; then
            echo "Homebrew tap push verification failed" >&2
            exit 1
        fi
    )
fi

echo
echo "Released $TAG"
echo "Release: $RELEASE_URL"
echo "DMG: $DOWNLOADS_DIR/$DMG_NAME"
echo "SHA-256: $DMG_SHA"
