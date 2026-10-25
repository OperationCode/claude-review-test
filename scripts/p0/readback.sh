#!/usr/bin/env bash
# Read an org ruleset back and check its workflow entries: repository_id, path, sha, no ref.
# Also checks: enforcement active, no bypass actors, and the ref_name include list equals
# P0_REF_INCLUDE (default refs/heads/p0-base; comma separated).
# Read-only.  scripts/p0/readback.sh <ruleset_id> <repository_id> <path> <sha>
set -euo pipefail
ORG=${ORG:-OperationCode}
id=${1:?ruleset id}; rid=${2:?repository id}; path=${3:?path}; sha=${4:?sha}
rs=$(gh api "orgs/$ORG/rulesets/$id")
jq '{name, enforcement, bypass_actors, conditions, rules: [.rules[] | {type, parameters}]}' <<<"$rs"
inc=${P0_REF_INCLUDE:-refs/heads/p0-base}
if jq -e --argjson rid "$rid" --arg p "$path" --arg s "$sha" --arg inc "$inc" '
  [.rules[] | select(.type == "workflows") | .parameters.workflows[]] as $w
  | ($w | length == 1) and ($w[0].repository_id == $rid) and ($w[0].path == $p)
    and ($w[0].sha == $s) and (($w[0] | has("ref")) | not)
    and (.enforcement == "active") and ((.bypass_actors // []) | length == 0)
    and ((.conditions.ref_name.include | sort) == ($inc | split(",") | sort))' <<<"$rs" >/dev/null; then
  echo "READBACK OK: one workflow entry, repository_id/path/sha match, no ref, active, no bypass, ref include $inc"
else
  echo "READBACK MISMATCH"; exit 1
fi
