#!/usr/bin/env bash
# Rank candidate repository topics by how many public repositories carry each one,
# so a repo's topic set is chosen from measured usage rather than from taste.
#
#   scripts/pick-topics.sh dart flutter pytorch on-device-ml executorch ...
#   scripts/pick-topics.sh --repo NaCode-Studios/Fluttorch              # score what is already set
#   scripts/pick-topics.sh --repo NaCode-Studios/Fluttorch quantization # both, deduplicated
#
# GitHub accepts at most 20 topics, and topics are how a repository is found by
# subject rather than by name, so an unused slot is a search that never reaches
# it. Fill all 20.
#
# Re-run at every minor release. The vocabulary moves: a set chosen once ages
# into the terms of the year it was written, and the repository keeps answering
# searches nobody makes any more.
#
# The count next to each candidate is the number of public repositories carrying
# that topic today. It is a usage signal, not a ranking of quality: a term with
# almost no carriers is a label rather than a route in, and a term with millions
# is one this repository will never surface in on its own. The set wants both,
# which is why the script reports and does not decide.
#
# One search API call per candidate, spaced to stay inside the 30-per-minute
# limit, so twenty candidates take about a minute.
set -euo pipefail

REPO=""; CANDIDATES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) CANDIDATES+=("$1"); shift ;;
  esac
done

if [[ -n "$REPO" ]]; then
  while IFS= read -r t; do [[ -n "$t" ]] && CANDIDATES+=("$t"); done \
    < <(gh api "repos/$REPO" --jq '.topics[]')
fi

[[ ${#CANDIDATES[@]} -eq 0 ]] && {
  echo "usage: $0 [--repo OWNER/REPO] [candidate ...]" >&2; exit 2; }

# Deduplicate, preserving the order they were given in.
UNIQUE=(); for t in "${CANDIDATES[@]}"; do
  [[ " ${UNIQUE[*]-} " == *" $t "* ]] || UNIQUE+=("$t")
done

# GitHub's own rules: lowercase letters, digits and hyphens, starting with a
# letter or digit, at most 35 characters. A candidate that breaks them is
# rejected by the API with a message that does not say which one it was.
INVALID=()
for t in "${UNIQUE[@]}"; do
  [[ "$t" =~ ^[a-z0-9][a-z0-9-]{0,34}$ ]] || INVALID+=("$t")
done
if [[ ${#INVALID[@]} -gt 0 ]]; then
  echo "not valid topics — lowercase letters, digits and hyphens, 35 characters at most:" >&2
  printf '  %s\n' "${INVALID[@]}" >&2
  exit 1
fi

count_repos () {                       # topic -> number of public repositories
  local t="$1" n
  n=$(gh api -X GET search/repositories -f q="topic:$t" -f per_page=1 \
        --jq '.total_count' 2>/dev/null) || n=""
  if [[ -z "$n" ]]; then               # almost always the search rate limit
    sleep 20
    n=$(gh api -X GET search/repositories -f q="topic:$t" -f per_page=1 \
          --jq '.total_count' 2>/dev/null) || n="?"
  fi
  printf '%s' "$n"
}

echo "Scoring ${#UNIQUE[@]} candidate(s). One search call each."
echo
ROWS=""
for t in "${UNIQUE[@]}"; do
  n=$(count_repos "$t")
  ROWS+="$n	$t"$'\n'
  printf '  %-36s %s\n' "$t" "$n"
  sleep 2
done

echo
echo "Ranked by repositories carrying the topic:"
echo
printf '%s' "$ROWS" | sort -rn | awk -F'\t' '
  { rank++
    thin = ($1 != "?" && $1+0 < 200) ? "  thin" : ""
    printf "  %2d. %-36s %10s%s\n", rank, $2, $1, thin }'

TOP=$(printf '%s' "$ROWS" | sort -rn | head -20 | cut -f2 | paste -sd, -)
N=${#UNIQUE[@]}
echo
if (( N > 20 )); then
  echo "$N candidates, and GitHub takes 20. The 20 with the most carriers:"
elif (( N < 20 )); then
  echo "$N candidates for 20 slots. $((20 - N)) searches this repository will not answer:"
else
  echo "All 20 slots filled:"
fi
echo
echo "  $TOP"
echo
echo "A thin topic is a judgement call, not a failure: keep it when it is the term"
echo "this project will be searched by as the field grows, drop it when it is a"
echo "label only this repository would ever apply to itself."
echo
echo "Then: scripts/set-repo-metadata.sh OWNER/REPO \"<description>\" \"$TOP\""
