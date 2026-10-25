#!/usr/bin/env bash
# Read an org ruleset back and check its workflow entries: repository_id, path, sha, no ref.
# Read-only.  scripts/p0/readback.sh <ruleset_id> <repository_id> <path> <sha>
set -euo pipefail
ORG=${ORG:-OperationCode}
id=${1:?ruleset id}; rid=${2:?repository id}; path=${3:?path}; sha=${4:?sha}
rs=$(gh api "orgs/$ORG/rulesets/$id")
jq '{name, enforcement, bypass_actors, conditions, rules: [.rules[] | {type, parameters}]}' <<<"$rs"
if jq -e --argjson rid "$rid" --arg p "$path" --arg s "$sha" '
  [.rules[] | select(.type == "workflows") | .parameters.workflows[]] as $w
  | ($w | length == 1) and ($w[0].repository_id == $rid) and ($w[0].path == $p)
    and ($w[0].sha == $s) and (($w[0] | has("ref")) | not)' <<<"$rs" >/dev/null; then
  echo "READBACK OK: one workflow entry, repository_id/path/sha match, no ref"
else
  echo "READBACK MISMATCH"; exit 1
fi
