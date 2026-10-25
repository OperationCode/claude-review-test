#!/usr/bin/env bash
# V9: spend limit behavior. Costs money. Run only against the TEST workspace with a very
# small hard spend limit (owner sets it in the Console). Sends small requests one at a
# time until the first non-200, at most MAX_CALLS. Logs status, request id, usage and
# the error body per call to v9-log.jsonl. Then read the workspace spend in the Console
# and record the overshoot = spend - limit.
#   ANTHROPIC_API_KEY=... MAX_CALLS=40 MAX_TOKENS=2000 scripts/p0/v9-spend.sh
# For the "gate fails closed" half, set P0_MESSAGES_CALL: "true" in the scratch
# p0-required.yml (federation rule bound to this workspace) and open a PR after the
# limit is hit: analyze must fail and the box must block.
set -uo pipefail
auth=()
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then auth=(-H "x-api-key: $ANTHROPIC_API_KEY")
elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then auth=(-H "authorization: Bearer $ANTHROPIC_AUTH_TOKEN")
else echo "set ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN (tiny-limit test workspace)"; exit 2; fi
max=${MAX_CALLS:-40}; mt=${MAX_TOKENS:-2000}
for i in $(seq 1 "$max"); do
  hdr=$(mktemp); out=$(mktemp)
  code=$(curl -sS -D "$hdr" -o "$out" -w '%{http_code}' https://api.anthropic.com/v1/messages \
    "${auth[@]}" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
    -d "{\"model\":\"claude-opus-5-5\",\"max_tokens\":$mt,\"output_config\":{\"effort\":\"low\"},\"messages\":[{\"role\":\"user\",\"content\":\"Write about $((mt/2)) words on the history of the bicycle.\"}]}")
  rid=$(grep -i '^request-id:' "$hdr" | tr -d '\r' | awk '{print $2}')
  jq -cn --arg i "$i" --arg t "$(date -u +%FT%TZ)" --arg code "$code" --arg rid "$rid" \
    --argjson b "$(jq -c '{stop_reason, usage, error, type}' "$out" 2>/dev/null || echo null)" \
    '{call:$i, t:$t, http:$code, request_id:$rid, body:$b}' | tee -a v9-log.jsonl
  rm -f "$hdr" "$out"
  [ "$code" = "200" ] || { echo "first non-200 at call $i: record the error type and message above"; exit 0; }
done
echo "no error after $max calls: raise MAX_CALLS or lower the workspace limit"
