#!/usr/bin/env bash
# Publish an UltraShot release to GitHub Releases end to end: preflight, build +
# notarize (scripts/release.sh), tag, push the tag, create the release with the
# DMG + zip + checksums.txt, verify.
#
# Usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]
# Env:   TEAM_ID         Apple team (else the gitignored .team-id); passed to release.sh
#        NOTARY_PROFILE  notarytool keychain profile (default: apple-notary)
#        GH_REPO         GitHub repo (default: christiancuri/ultrashot)
#
# Tags are v<x.y.z>; the build number is `git rev-list --count HEAD` (always
# grows on main). Release notes come from the "## <x.y.z>" section of CHANGELOG.md.
# DRY_RUN=1 reports blockers as warnings and prints the plan: nothing is built,
# tagged, pushed or released.
set -euo pipefail

TAG_PREFIX="v"
GH_REPO="${GH_REPO:-christiancuri/ultrashot}"
NOTARY_PROFILE="${NOTARY_PROFILE:-apple-notary}"
APP_TITLE="UltraShot"

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# version_gt <a> <b>: true when a > b (numeric x.y.z compare).
version_gt() {
  local IFS=. a b i
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do
    ((10#${a[i]} > 10#${b[i]})) && return 0
    ((10#${a[i]} < 10#${b[i]})) && return 1
  done
  return 1
}

# Latest vX.Y.Z tag reachable from HEAD, without the prefix (empty when none).
last_tag_version() {
  git tag --list "${TAG_PREFIX}*" --merged HEAD | sed "s/^$TAG_PREFIX//" \
    | { grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# changelog_section <file> <version>: body of "## <version>" (heading may carry
# a suffix such as " - 2026-11-03"), up to the next "## " heading, trimmed.
changelog_section() {
  awk -v v="$2" '
    /^## / {
      if (found) exit
      h = substr($0, 4); sub(/^\[/, "", h)
      if (h == v || index(h, v " ") == 1 || index(h, v "]") == 1) { found = 1; next }
    }
    found { print }
  ' "$1" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
}

main() {
  cd "$(dirname "$0")/.."
  local ROOT="$PWD" DIST WORK
  DIST="$ROOT/build/release/dist"
  WORK="$ROOT/build/release/publish"
  local DRY="${DRY_RUN:-0}"
  # In a dry run, problems that would block a real publish are only reported.
  blocker() { if [[ "$DRY" == 1 ]]; then warn "$* (ignored in DRY_RUN)"; else die "$*"; fi; }

  local version="${VERSION:-}"
  [[ -n "$version" ]] || die "usage: make publish VERSION=x.y.z [YES=1] [DRY_RUN=1]"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must be x.y.z (got '$version')"
  local tag="$TAG_PREFIX$version"

  step "Preflight"
  local cmd
  for cmd in git gh xcrun xcodegen shasum awk; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required"
  done
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
  if [[ -z "${TEAM_ID:-}" && ! -s .team-id ]]; then
    blocker "no team id: set TEAM_ID or create .team-id (gitignored)"
  fi

  local branch dirty
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == main ]] || blocker "publish runs on main only (current branch: $branch)"
  dirty="$(git status --porcelain --untracked-files=normal)"
  [[ -z "$dirty" ]] || blocker "working tree is dirty; commit or stash first:
$dirty"
  git fetch --quiet origin main --tags || die "git fetch origin failed"
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || blocker "HEAD is not origin/main (pull or push first so the tag points at a published commit)"

  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && blocker "tag $tag already exists locally"
  [[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ]] || blocker "tag $tag already exists on origin"
  gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1 && blocker "release $tag already exists on $GH_REPO"

  local prev_version
  prev_version="$(last_tag_version)"
  if [[ -n "$prev_version" ]]; then
    version_gt "$version" "$prev_version" || blocker "VERSION $version is not newer than $prev_version"
  fi

  mkdir -p "$WORK"
  local notes_md="$WORK/notes-$version.md"
  if [[ -f CHANGELOG.md ]]; then
    changelog_section CHANGELOG.md "$version" >"$notes_md"
  else
    : >"$notes_md"
  fi
  if [[ ! -s "$notes_md" ]]; then
    blocker "CHANGELOG.md has no (or an empty) '## $version' section; add the release notes first"
    printf -- '- (DRY_RUN placeholder: no CHANGELOG.md section for %s)\n' "$version" >"$notes_md"
  fi

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "notary profile: $NOTARY_PROFILE"
  else
    blocker "notary profile '$NOTARY_PROFILE' not usable (scripts/release.sh prints how to create it)"
  fi

  local build dmg zip sums
  build="$(git rev-list --count HEAD)"
  dmg="$DIST/UltraShot-$version.dmg"
  zip="$DIST/UltraShot-$version.zip"
  sums="$DIST/checksums.txt"
  echo "repo:     $GH_REPO"
  echo "previous: ${prev_version:-none (first release)}"
  echo "next:     $version (build $build, tag $tag)"

  if [[ "$DRY" == 1 ]]; then
    step "Plan (DRY_RUN=1: nothing was built, tagged, pushed or released)"
    cat <<PLAN
1. scripts/release.sh $version --build $build   (archive, Developer ID, notarize, staple)
   -> $dmg
   -> $zip
   -> $sums
2. git tag -a $tag -m "$APP_TITLE $version (build $build)"
3. git push origin $tag
4. gh release create $tag <dmg> <zip> checksums.txt --repo $GH_REPO \\
     --title "$APP_TITLE $version" --notes-file $notes_md --verify-tag --latest
5. gh release view $tag: the DMG, zip and checksums.txt assets are present

release notes ($notes_md):
$(sed 's/^/  | /' "$notes_md")
PLAN
    return 0
  fi

  if [[ "${YES:-0}" != 1 ]]; then
    local answer
    printf '\npublish %s %s (build %s) to %s? [y/N] ' "$APP_TITLE" "$version" "$build" "$GH_REPO"
    read -r answer </dev/tty || answer=""
    [[ "$answer" == [yY]* ]] || die "aborted"
  fi

  step "Building $version ($build)"
  NOTARY_PROFILE="$NOTARY_PROFILE" scripts/release.sh "$version" --build "$build"
  local f
  for f in "$dmg" "$zip" "$sums"; do
    [[ -f "$f" ]] || die "release did not produce $f"
  done

  step "Tagging $tag"
  git tag -a "$tag" -m "$APP_TITLE $version (build $build)"
  git push origin "refs/tags/$tag" || die "tag push failed; retry: git push origin $tag"

  step "Creating GitHub release $tag"
  gh release create "$tag" "$dmg" "$zip" "$sums" --repo "$GH_REPO" \
    --title "$APP_TITLE $version" --notes-file "$notes_md" --verify-tag --latest \
    || die "gh release create failed; the tag $tag is pushed. Fix and re-run the gh release create by hand"

  step "Verifying"
  local assets name
  assets="$(gh release view "$tag" --repo "$GH_REPO" --json assets -q '.assets[].name')"
  for name in "$(basename "$dmg")" "$(basename "$zip")" checksums.txt; do
    grep -qxF "$name" <<<"$assets" || die "release $tag is missing asset $name"
  done
  gh release view "$tag" --repo "$GH_REPO" --json tagName,name,isDraft,isPrerelease,url \
    -q '"\(.name) (\(.tagName)) draft=\(.isDraft) prerelease=\(.isPrerelease)\n\(.url)"'

  step "Published $APP_TITLE $version (build $build)"
  echo "tag:      $tag"
  echo "download: https://github.com/$GH_REPO/releases/download/$tag/$(basename "$dmg")"
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
