#!/usr/bin/env bash
# Writes the release notes for one version to stdout, in Markdown.
#
#   tool/release/release_notes.sh <version> [<previous tag>] [<head ref>]
#
# The notes hold the version's CHANGELOG.md section, then every non-merge
# commit since the previous tag (all history when there is none), then a
# compare link. The tag-version workflow uses them for both the annotated
# tag message and the GitHub Release.
set -euo pipefail

version="${1:?usage: release_notes.sh <version> [<previous tag>] [<head ref>]}"
prev_tag="${2:-}"
head_ref="${3:-HEAD}"
repo_url="${REPO_URL:-https://github.com/rsagar024/sealed_trace}"

# The CHANGELOG section: from "## <version>" up to the next "## " heading.
changelog="$(awk -v v="$version" '
  $0 ~ "^## " { if (found) exit; if ($2 == v) { found = 1; next } }
  found { print }
' CHANGELOG.md)"

if [[ -n "$prev_tag" ]]; then
  range="$prev_tag..$head_ref"
else
  range="$head_ref"
fi
commits="$(git log --no-merges --format='- %s (%h, %an)' "$range")"
commit_count="$(git rev-list --no-merges --count "$range")"

echo "# sealed_trace v$version"
echo
echo "Released from \`master\` at $(git rev-parse --short "$head_ref") on $(date -u +%Y-%m-%d)."
echo
echo "Install:"
echo
echo '```yaml'
echo 'dependencies:'
echo "  sealed_trace: ^$version"
echo '```'
echo
echo "## What's new"
echo
if [[ -n "${changelog//[[:space:]]/}" ]]; then
  printf '%s\n' "$changelog"
else
  echo "No CHANGELOG.md entry for $version."
fi
echo
if [[ -n "$prev_tag" ]]; then
  echo "## Commits since $prev_tag ($commit_count)"
else
  echo "## Commits ($commit_count)"
fi
echo
printf '%s\n' "$commits"
echo
if [[ -n "$prev_tag" ]]; then
  echo "**Full diff:** $repo_url/compare/$prev_tag...v$version"
else
  echo "**Full history:** $repo_url/commits/v$version"
fi
