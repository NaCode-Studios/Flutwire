#!/usr/bin/env bash
# Apply the house repository settings: description, topics, and optionally the homepage.
#
#   scripts/set-repo-metadata.sh OWNER/REPO "one-line description" "topic,topic,..." [homepage-url]
#
# The homepage is optional on purpose: linking a page that does not exist yet is
# worse than linking nothing. Pass it once the page is live.
#
# The social preview cannot be set through the API. Upload
# docs/brand/<name>-social-preview.png under Settings → General → Social preview.
set -euo pipefail

REPO="${1:-}"; DESC="${2:-}"; TOPICS="${3:-}"; HOME_URL="${4:-}"
[[ -z "$REPO" || -z "$DESC" || -z "$TOPICS" ]] && {
  echo "usage: $0 OWNER/REPO \"description\" \"topic,topic,...\" [homepage]" >&2; exit 2; }

n=$(tr ',' '\n' <<<"$TOPICS" | grep -c .)
if (( n > 20 )); then
  echo "error: $n topics — GitHub accepts at most 20" >&2; exit 1
elif (( n < 20 )); then
  echo "note: $n topics — GitHub allows 20, and $((20 - n)) unused slots are $((20 - n)) searches" >&2
  echo "      this repository will not answer. scripts/pick-topics.sh ranks candidates." >&2
fi

args=(--description "$DESC")
[[ -n "$HOME_URL" ]] && args+=(--homepage "$HOME_URL")
while IFS= read -r t; do
  [[ -n "$t" ]] && args+=(--add-topic "$(tr -d '[:space:]' <<<"$t")")
done < <(tr ',' '\n' <<<"$TOPICS")

gh repo edit "$REPO" "${args[@]}"

echo
gh repo view "$REPO" --json description,homepageUrl,repositoryTopics,visibility \
  --jq '"description: \(.description)\nhomepage:    \(.homepageUrl // "(unset — set it when the page exists)")\ntopics:      \(.repositoryTopics|map(.name)|join(", "))\nvisibility:  \(.visibility)"'

echo
if gh api "repos/$REPO/branches/main/protection" >/dev/null 2>&1; then
  echo "main: protected"
else
  echo "main: NOT protected — pull-request-only requires a paid plan on a private repo."
  echo "      Do not assume it is on; either make the repo public, upgrade, or record that it is off."
fi
echo "social preview: upload docs/brand/*-social-preview.png in Settings → General (no API)"
