#!/usr/bin/env bash
# V16: read-only. Prints the PR timeline events that move the push epoch (with server
# times and actors), plus the other head events, then judges every "/p0 override <sha>"
# comment by the spec rule: exact SHA (current head unless given), never edited, created
# strictly after the push epoch. A comment posted for A before a force push must show
# "rejected".
#
#   scripts/p0/v16-check.sh <pr> [head_sha]
set -euo pipefail
R=${R:-OperationCode/claude-review-test}
pr=${1:?pr number}
head=${2:-$(gh api "repos/$R/pulls/$pr" --jq .head.sha)}
tl=$(gh api --paginate "repos/$R/issues/$pr/timeline?per_page=100" --jq '.[]' | jq -s '.')
echo "== timeline (head and base events)"
jq -r '.[] | select(.event | test("head_ref|base_ref|closed|reopened|committed|force|ready_for_review|convert_to_draft")) |
  [(.created_at // .committer.date // "-"), .event, ((.actor // .user // {}).login // "-"), ((.before // "")|.[0:7]), ((.after // .sha // "")|.[0:7])] | @tsv' <<<"$tl"
epoch=$(jq -r '[.[] | select(.event == "head_ref_force_pushed" or .event == "head_ref_deleted" or .event == "head_ref_restored" or .event == "base_ref_changed") | .created_at] | max // ""' <<<"$tl")
echo "== push epoch: ${epoch:-<none>}   head: $head"
echo "== override comments"
gh api --paginate "repos/$R/issues/$pr/comments?per_page=100" \
  --jq '.[] | select(.body | startswith("/p0 override")) | [.id, .user.login, .author_association, .created_at, .updated_at, (.body | split("\n")[0])] | @tsv' |
while IFS=$'\t' read -r id user assoc created updated body; do
  verdict=accepted; why=""
  [ "$body" = "/p0 override $head" ] || { verdict=rejected; why+=" sha"; }
  [ "$created" = "$updated" ] || { verdict=rejected; why+=" edited"; }
  if [ -n "$epoch" ] && [[ ! "$created" > "$epoch" ]]; then verdict=rejected; why+=" before-epoch"; fi
  case "$assoc" in OWNER|MEMBER|COLLABORATOR) ;; *) verdict=rejected; why+=" association=$assoc";; esac
  printf '%s\t%s\t%s\t%s\t%s%s\n' "$id" "$user" "$created" "$verdict" "${why:+because}" "$why"
done
