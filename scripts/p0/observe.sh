#!/usr/bin/env bash
# Phase 0 observer (V6, V24, V4). Read-only. Polls one PR every N seconds and appends one
# JSON line per poll: local time, PR state, head SHA, merge box state, review decision,
# the runs of the required workflow on the current head SHA, and every other check or
# status on the PR (other_checks), so a Blocked box can be checked for other blockers.
#
#   scripts/p0/observe.sh <pr> [interval_s=5] [workflow_name=p0-required] [out=p0-observe-<pr>.jsonl]
#
# Merge box words (same mapping as TESTING-T5.md): CLEAN, UNSTABLE, HAS_HOOKS = Mergeable;
# BLOCKED = Blocked; anything else (UNKNOWN, BEHIND, DIRTY, DRAFT) = Other, re-read it.
# Use a token WITHOUT bypass on the test ruleset (the test ruleset has no bypass actors).
# Stop with Ctrl-C.
set -uo pipefail
R=${R:-OperationCode/claude-review-test}
pr=${1:?pr number}; interval=${2:-5}; wf=${3:-p0-required}; out=${4:-p0-observe-$pr.jsonl}
prev=""
while :; do
  t=$(date -u +%FT%TZ)
  pv=$(gh pr view "$pr" --repo "$R" --json state,headRefOid,baseRefName,mergeStateStatus,mergeable,reviewDecision,isDraft,statusCheckRollup 2>/dev/null || echo '{}')
  head=$(jq -r '.headRefOid // ""' <<<"$pv")
  runs='[]'
  if [ -n "$head" ]; then
    runs=$(gh api "repos/$R/actions/runs?head_sha=$head&per_page=100" \
      --jq "[.workflow_runs[] | select(.name == \"$wf\" or (.path | contains(\"$wf\"))) | {id, run_attempt, event, status, conclusion, created_at, updated_at, path}]" 2>/dev/null || echo '[]')
  fi
  line=$(jq -cn --arg t "$t" --arg wf "$wf" --argjson pv "$pv" --argjson runs "$runs" '
    {t:$t, pr_state:$pv.state, draft:$pv.isDraft, base:$pv.baseRefName, head:$pv.headRefOid, merge_state:$pv.mergeStateStatus,
     box:(if ($pv.mergeStateStatus|tostring|test("^(CLEAN|UNSTABLE|HAS_HOOKS)$")) then "Mergeable"
          elif $pv.mergeStateStatus == "BLOCKED" then "Blocked" else "Other" end),
     mergeable:$pv.mergeable, review:$pv.reviewDecision,
     newest_run:($runs | max_by(.id) // null), runs:$runs,
     other_checks:[($pv.statusCheckRollup // [])[] | select((.workflowName // "") != $wf)
       | {name:(.name // .context), workflow:.workflowName, status:(.status // .state), conclusion}]}')
  echo "$line" >> "$out"
  # Print a short line only when something changed.
  short=$(jq -r '[.pr_state, (.head // "" | .[0:7]), .box, .merge_state,
    ((.newest_run // {}) | "\(.id // "-") a\(.run_attempt // "-") \(.status // "-")/\(.conclusion // "-")"), (.runs | length)] | @tsv' <<<"$line")
  if [ "$short" != "$prev" ]; then echo "$t	$short"; prev=$short; fi
  sleep "$interval"
done
