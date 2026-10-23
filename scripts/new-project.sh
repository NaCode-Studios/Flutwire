#!/usr/bin/env bash
# Create (or repair) the GitHub Project for a library, with the house field set and views.
#
#   scripts/new-project.sh <library-name> [--owner ORG] [--tiers "A,B,C"] [--areas "A,B,C"]
#
# Idempotent: run it again after an interrupted run and it fills in what is missing.
#
# Two things the API cannot do, so they stay manual:
#   · view filters, grouping and visible columns — configure once in the interface
#   · the social preview image — Settings → General → Social preview
set -euo pipefail

NAME="${1:-}"
[[ -z "$NAME" ]] && { echo "usage: $0 <library-name> [--owner ORG] [--tiers ...] [--areas ...]" >&2; exit 2; }
shift

OWNER="NaCode-Studios"
TIERS="Tier 0,Tier 1,Tier 2,Maintenance"
AREAS="Core,Build & CI,Docs & examples"
DESC=""
STATUS="ON_TRACK"
START=""
TARGET=""
BODY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --tiers) TIERS="$2"; shift 2 ;;
    --areas) AREAS="$2"; shift 2 ;;
    --description) DESC="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --body-file) BODY_FILE="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

say() { printf '  %s\n' "$*"; }

# ── the project ────────────────────────────────────────────────────────────────
NUM=$(gh project list --owner "$OWNER" --format json --limit 100 \
      | python3 -c "
import json,sys
t=sys.argv[1]
print(next((str(p['number']) for p in json.load(sys.stdin)['projects'] if p['title']==t), ''))
" "$NAME")

if [[ -z "$NUM" ]]; then
  NUM=$(gh project create --owner "$OWNER" --title "$NAME" --format json --jq '.number')
  say "created project #$NUM"
else
  say "project #$NUM already exists"
fi

gh project edit "$NUM" --owner "$OWNER" --visibility PUBLIC >/dev/null
if [[ -n "$DESC" ]]; then
  gh project edit "$NUM" --owner "$OWNER" --description "$DESC" >/dev/null
  say "public, described"
else
  say "public — NO DESCRIPTION SET."
  say "  Pass --description with a sentence only this project could say: what it is,"
  say "  and the one principle or fact that governs its decisions. Do not reuse a"
  say "  sibling's sentence with the name swapped."
fi

PID=$(gh project view "$NUM" --owner "$OWNER" --format json --jq '.id')

# ── Status: replace the default options with the house vocabulary ──────────────
SFID=$(gh project field-list "$NUM" --owner "$OWNER" --format json \
       --jq '.fields[] | select(.name=="Status") | .id')
gh api graphql -f f="$SFID" -f query='mutation($f:ID!){
 updateProjectV2Field(input:{fieldId:$f, singleSelectOptions:[
  {name:"Planned",      color:GRAY,   description:"Not started, no version assigned yet."},
  {name:"In progress",  color:YELLOW, description:"Merged under [Unreleased], targeting the version in Target version."},
  {name:"Shipped",      color:GREEN,  description:"Released. Target version names the release and matches CHANGELOG.md."},
  {name:"Post-1.0",     color:BLUE,   description:"Deliberately deferred beyond 1.0."},
  {name:"Deferred",     color:ORANGE, description:"Pushed to a later milestone. Decision note gives the reason."},
  {name:"Declined",     color:RED,    description:"Decided against. Decision note gives the reason."}]}){
  projectV2Field{ ... on ProjectV2SingleSelectField { id } } } }' >/dev/null
say "Status vocabulary set"

# ── the rest of the field set ─────────────────────────────────────────────────
has_field() {
  gh project field-list "$NUM" --owner "$OWNER" --format json --jq '.fields[].name' | grep -qxF "$1"
}
add_select() {
  has_field "$1" && { say "· $1 (already there)"; return; }
  gh project field-create "$NUM" --owner "$OWNER" --name "$1" \
    --data-type SINGLE_SELECT --single-select-options "$2" >/dev/null
  say "· $1"
}
add_plain() {
  has_field "$1" && { say "· $1 (already there)"; return; }
  gh project field-create "$NUM" --owner "$OWNER" --name "$1" --data-type "$2" >/dev/null
  say "· $1"
}

add_select "Tier"     "$TIERS"
add_select "Area"     "$AREAS"
add_select "Effort"   "S,M,L,XL"
add_select "Priority" "P0 · Next up,P1 · High,P2 · Medium,P3 · Low"
add_select "Kind"     "Milestone,Feature,Bug,Docs,Chore,Dependency,Release"
add_plain  "Target version"  TEXT
add_plain  "Exit criterion"  TEXT
add_plain  "Decision note"   TEXT
add_plain  "Start date"      DATE
add_plain  "Target date"     DATE

# ── the six views ─────────────────────────────────────────────────────────────
# The default view is renamed rather than deleted, so the project never has a
# stray "View 1" alongside the real board.
VIEWS=$(gh api graphql -f o="$OWNER" -F n="$NUM" -f query='
 query($o:String!,$n:Int!){ organization(login:$o){ projectV2(number:$n){
   views(first:20){ nodes{ id name } } } } }' \
 --jq '.data.organization.projectV2.views.nodes[] | "\(.name)"')

if ! grep -qx "Roadmap board" <<<"$VIEWS"; then
  VID=$(gh api graphql -f o="$OWNER" -F n="$NUM" -f query='
   query($o:String!,$n:Int!){ organization(login:$o){ projectV2(number:$n){
     views(first:1){ nodes{ id } } } } }' --jq '.data.organization.projectV2.views.nodes[0].id')
  gh api graphql -f v="$VID" -f query='mutation($v:ID!){
    updateProjectV2View(input:{viewId:$v,name:"Roadmap board",layout:BOARD_LAYOUT}){
      projectV2View{ id } } }' >/dev/null
  say "· Roadmap board (renamed from the default view)"
fi

for spec in "Next up:TABLE_LAYOUT" "Shipped:TABLE_LAYOUT" \
            "Decisions & deferrals:TABLE_LAYOUT" "Timeline:ROADMAP_LAYOUT" \
            "Maintenance:TABLE_LAYOUT"; do
  vname="${spec%:*}"; layout="${spec##*:}"
  grep -qxF "$vname" <<<"$VIEWS" && { say "· $vname (already there)"; continue; }
  gh api graphql -f p="$PID" -f n="$vname" -f query="mutation(\$p:ID!,\$n:String!){
    createProjectV2View(input:{projectId:\$p,name:\$n,layout:$layout}){
      projectV2View{ id } } }" >/dev/null
  say "· $vname"
done

# ── the status update ─────────────────────────────────────────────────────────
# Without one the project shows no label in the org list and reads as abandoned
# next to the projects that have one.
HAS_UPDATE=$(gh api graphql -f o="$OWNER" -F n="$NUM" -f query='
 query($o:String!,$n:Int!){ organization(login:$o){ projectV2(number:$n){
   statusUpdates(last:1){ nodes{ status } } } } }' \
 --jq '.data.organization.projectV2.statusUpdates.nodes | length')

if [[ "$HAS_UPDATE" == "0" ]]; then
  if [[ -n "$BODY_FILE" && -n "$START" && -n "$TARGET" ]]; then
    gh api graphql -F body="@$BODY_FILE" -f pid="$PID" \
      -f s="$STATUS" -f sd="$START" -f td="$TARGET" -f query='
      mutation($pid:ID!,$body:String!,$s:ProjectV2StatusUpdateStatus!,$sd:Date!,$td:Date!){
        createProjectV2StatusUpdate(input:{projectId:$pid,status:$s,startDate:$sd,
          targetDate:$td,body:$body}){ statusUpdate{ status } } }' >/dev/null
    say "status update: $STATUS  $START → $TARGET"
  else
    say "NO STATUS UPDATE — pass --status, --start, --target and --body-file."
    say "  ON_TRACK means the work that matters has a path; AT_RISK means it has an"
    say "  unresolved dependency — evidence, a signature, hardware or hours. The body"
    say "  opens with one sentence on where things actually stand, bad part included."
  fi
else
  say "status update already present"
fi

cat <<EOF

Project ready: https://github.com/orgs/$OWNER/projects/$NUM

Two steps left that no API covers:
  1. Configure each view's filter, grouping and columns once, in the interface.
     Roadmap board groups by Status · Next up sorts by Priority and filters
     Status:Planned · Shipped filters Status:Shipped · Decisions & deferrals
     filters Status:Deferred,Declined · Timeline uses Start date and Target date
     · Maintenance filters Kind:Bug,Chore,Dependency.
  2. Add the milestones as "M# · Title", then create one repository milestone
     per tier and assign every issue to it. The board is written first.
     Note that a draft issue's title is edited through its *content* id (DI_...),
     not the item id (PVTI_...); field values use the item id.
EOF
