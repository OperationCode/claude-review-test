# Test T5: org ruleset rule "Require workflows to pass before merging"

Local design. Nothing here is pushed. The owner (`irvingpop`, org admin) runs every step. No second account is needed: the owner forks the repo to the owner account.

## Questions

| Q | Question |
|---|----------|
| Q2 | Can a same-name job from a fork PR's own workflow satisfy (a) a plain required-status-check rule (expected yes, positive control) and (b) the org workflows rule (we hope no)? |
| Q1 | Does the org workflows rule run on same-repo and fork PRs, and does its result block or allow the merge? (sanity for Q2) |
| Q3 | Can the required workflow call a reusable workflow (`workflow_call`) and pass the PR number? |
| Q4 | Does the ruleset accept a pinned `sha` and keep running it after `main` moves? Does a same-path edit in a PR replace the required run? |

## Design

```
 org ruleset "t5-required-workflows" (target: claude-review-test only, default branch)
   rule: workflows -> repository_id 1432457406, .github/workflows/t5-required.yml @ refs/heads/main
 t5-required.yml       job "t5-gate"  result = repo variable T5_GATE (failure fails, else passes)
 t5-required-call.yml  job "t5-call" -> t5-callee.yml (workflow_call), result = T5_CALL_GATE
 test-fixtures/t5-forgery.yml       forged "t5-gate", always passes (PR branch, event pull_request)
 test-fixtures/t5-forgery-edit.yml  same-path edit of t5-required.yml, always passes
 repo ruleset "t5-name-control"     plain required status check "t5-gate" (name-bound control)
```

PRs: A = same-repo, no forgery (control). C = same-repo forgery. D = fork forgery. E = same-path edit. PR #4 (kylemh, outsider fork) is read-only.

The required file lives in `claude-review-test` itself, so it also runs as a NORMAL `pull_request_target` workflow. Keep that normal workflow DISABLED (`gh workflow disable t5-required.yml`) in every row except K2. Then the only `t5-gate` runs on a head are the ruleset run (Checks tab marks it "Required") and the forged run.

Scope: owner-made fork PRs do not exercise the outsider approval gate (`first_time_contributors`). A different-repo same-path attack is not tested. Both are follow-ups.

## Rules for every row

1. Fresh head SHA per row. Set the variables FIRST, then run `bump` (an empty commit pushed to the PR branch). Do not close and reopen: that keeps the old SHA and its old runs.
2. A row reads only runs of its own head SHA (`rd` below prints them).
3. Wait until every check run of the head is `completed`, then read twice, 10 seconds apart.

```sh
cd /Users/irving/src/operationcode/claude-review-test
R=OperationCode/claude-review-test
# bump <branch> <label> <remote>   remote: git@github.com:$R.git, or "fork" for PR D
bump() { git switch -q "$1" && git commit --allow-empty -qm "t5 $2" && git push -q "$3" "$1"; }
# rd <pr>   merge box + every check run of the current head
rd() { sleep 10; H=$(gh pr view "$1" --repo $R --json headRefOid --jq .headRefOid)
  echo "PR $1 head ${H:0:7}"; gh pr view "$1" --repo $R --json mergeStateStatus --jq .mergeStateStatus
  gh api repos/$R/commits/$H/check-runs --jq '.check_runs[]|[.name,.status,.conclusion,.id]|@tsv'; }
```

`mergeStateStatus` is the merge box: `CLEAN` can merge, `BLOCKED` a required rule is not met. Do not use `statusCheckRollup.state`. As org admin you see a bypass option on a BLOCKED PR. Do not use it. Read the real check names in the merge box and write them down (a required workflow can show a longer name).

## Phase 0. Setup

| # | Action | Expected |
|---|--------|----------|
| 0.1 | `gh auth refresh -h github.com -s admin:org` | token can write org rulesets |
| 0.2 | `gh api repos/$R/rulesets/25791558 > results-T5-require-scn.json` (in the repo dir, do not commit) | saved |
| 0.3 | `gh api -X PUT repos/$R/rulesets/25791558 -f enforcement=disabled` | `disabled`. Only the T5 rules gate. While `t5-name-control` or the org rule is active, direct pushes to `main` and merges of open PRs #2, #3, #5, #6, #7 are blocked. Keep the test short. |
| 0.4 | `git push git@github.com:$R.git t5-required-workflows`, open a PR to `main`, merge it | `main` has the workflows and fixtures (SSH push; HTTPS needs the `workflow` scope) |
| 0.5 | `git switch main && git pull; S1=$(git rev-parse HEAD)` | `S1` = commit with `WORKFLOW_VERSION: v1` |
| 0.6 | `gh variable set T5_GATE --repo $R --body success; gh variable set T5_CALL_GATE --repo $R --body success` | 2 variables |
| 0.7 | `gh workflow disable t5-required.yml --repo $R; gh workflow disable t5-required-call.yml --repo $R` | normal runs off. `t5-callee.yml` is `workflow_call` only. |
| 0.8 | PR A: `git switch -c t5-ctrl main`, add a line to `README.md`, commit, push, `gh pr create --repo $R --base main --head t5-ctrl --title "t5 control" --body "T5 control"` | note number |
| 0.9 | PR C: `git switch -c t5-forge-same main; mkdir -p .github/workflows; cp test-fixtures/t5-forgery.yml .github/workflows/`, commit, push, open PR (`--head t5-forge-same`) | forgery file only |
| 0.10 | PR D: `gh repo fork $R --clone=false; git remote add fork git@github.com:irvingpop/claude-review-test.git`. Sync the fork (`gh repo sync irvingpop/claude-review-test`). `git switch -c t5-forge-fork main`, copy the same file, commit, `git push fork t5-forge-fork`, `gh pr create --repo $R --base main --head irvingpop:t5-forge-fork --title "t5 forgery fork" --body "T5 Q2"` | forgery file only |
| 0.11 | `gh api orgs/OperationCode/rulesets` | no `t5` ruleset yet |

Fork PR runs can wait for approval: the owner needs none. If a run shows "Approve and run", write it down and do not approve.

## Phase K. Q2 (a): plain required-status-check rule (org ruleset not created yet)

```sh
gh api -X POST repos/$R/rulesets --input test-fixtures/ruleset/t5-repo-name-control.json   # note id as $NR
```

| # | Real `t5-gate` | Setup, then `bump` each PR | PR | Expected | Meaning |
|---|---|---|---|---|---|
| K1 | absent (normal workflow disabled) | none | C, D | `CLEAN` | POSITIVE CONTROL: a forged same-name job satisfies a name rule. If `BLOCKED`, the fixture does not work: stop and fix. |
| K2 | fail | `gh workflow enable t5-required.yml --repo $R`, `T5_GATE=failure` | C, D | record `BLOCKED` or `CLEAN` | does a real fail plus a forged pass under one name block? Decides whether W1 can discriminate. |

Then: `gh workflow disable t5-required.yml --repo $R; gh variable set T5_GATE --repo $R --body success; gh api -X DELETE repos/$R/rulesets/$NR`.

## Phase W. Q1 and Q2 (b): org workflows rule

```sh
gh api -X POST orgs/OperationCode/rulesets --input test-fixtures/ruleset/t5-org-ruleset.json   # HTTP 201, note id as $RS
gh api orgs/OperationCode/rulesets/$RS --jq '.conditions,.rules'   # include = ["claude-review-test"] only
```

If the POST returns 422 or 403 on the `workflows` rule: stop, record the exact status and text, do not assume the cause. The normal workflow stays disabled.

| # | Real (ruleset) `t5-gate` | Setup, then `bump` | PR | Expected | Meaning |
|---|---|---|---|---|---|
| W0 | pass | `T5_GATE=success` | A | the Required run starts, no approval click. `CLEAN`. | Q1 sanity. Also record `gh api repos/$R/actions/runs/<id> --jq '{event,path,name}'` of the Required run. If no run starts with the normal workflow disabled, the ruleset run depends on it: record, mark all W rows confounded. |
| W0b | fail | `T5_GATE=failure` | A | `BLOCKED` | Q1: the result gates the merge |
| W1 | fail, forged pass | `T5_GATE=failure` | C, D | `BLOCKED` | Q2 (b). `CLEAN` means the forged job satisfies the workflows rule. |
| W2 | outsider fork | close and reopen PR #4 (no push possible) | #4 | run starts? approval needed? | Q1 outsider read, record only |

## Decision (Q2)

| K1 | K2 | W1 | Result |
|---|---|---|---|
| `BLOCKED` | any | any | invalid, fixture broken, fix and rerun |
| `CLEAN` | `CLEAN` | `BLOCKED` | workflows rule is bound to the workflow, not the job name. Forgery fails. |
| `CLEAN` | any | `CLEAN` | forgery WORKS against the workflows rule. Finding: the reviewer gate cannot rely on it alone. |
| `CLEAN` | `BLOCKED` | `BLOCKED` | OPEN. A real fail blocks under both hypotheses. Do not claim either result. Follow-up: real job pending state (`sleep` variant), forged job finishing later. |

## Phase B. Q3 (reusable workflow)

Normal runs of both files stay disabled (0.7), so only the ruleset runs exist.

| # | Setup, then `bump` A | Expected |
|---|---|---|
| B1 | `gh api -X PUT orgs/OperationCode/rulesets/$RS --input test-fixtures/ruleset/t5-org-ruleset-phaseB.json` (200, 2 workflows). `T5_GATE=success`, `T5_CALL_GATE=success` | the Required run `t5-call` starts and calls `t5-callee`. `CLEAN`. Summary: `input pr_number` and the event PR number both equal A. Write down `workflow_ref`. |
| B2 | `T5_CALL_GATE=failure` | `BLOCKED` by the call alone (T5_GATE is success) |

Q3 is YES when B1 shows the number and B2 blocks. If no run starts, a required workflow cannot use `workflow_call` here; the design must be self-contained. Then `T5_CALL_GATE=success`.

## Phase C. Q4 (sha pin, same-path edit)

| # | Action | Expected |
|---|--------|----------|
| C1 | In `test-fixtures/ruleset/t5-org-ruleset-phaseC-sha.json` replace `REPLACE_WITH_40_CHAR_COMMIT_SHA` with `$S1`, then `PUT orgs/OperationCode/rulesets/$RS --input` that file. `T5_GATE=success`. `bump` A. | HTTP 200, response echoes `sha`. If 422 on `sha` alone: record the text, retry with `"ref": "refs/heads/main"` added. Run summary: `workflow_sha` = `$S1`, `version: v1`. |
| C2 | PR "t5-v2": branch from `main`, change `v1` to `v2` in `.github/workflows/t5-required.yml`, merge it (the pinned v1 run must pass). `bump` A. | the ruleset run still shows `v1`, `workflow_sha` = `$S1`. The pin holds. |
| C3 | `PUT` the original `t5-org-ruleset.json` back. `T5_GATE=failure`. PR E: `git switch -c t5-edit main; cp test-fixtures/t5-forgery-edit.yml .github/workflows/t5-required.yml`, commit, push, open PR. | Runs on the head: PR copy (event `pull_request`, summary `edited-by-pr`) passes; ruleset run (Required) fails. Merge box `BLOCKED`. Valid only if K2 is `CLEAN` (else this row is the same non-discriminating mix as W1). `CLEAN` means the PR copy replaced the required run: finding. |

Q4 pin is YES when C1 is 200 and C2 shows `v1`.

## Evidence

Per row: `rd` output (head SHA, merge box, check runs), run ids, the check names as shown, HTTP status and body of each ruleset call. Save to `results-T5.md` in the repo dir (no secrets).

## Cleanup

If the test stops at ANY point, run the first block first. IDs are looked up by name, so a lost shell variable does not matter.

```sh
RS=$(gh api orgs/OperationCode/rulesets --jq '.[]|select(.name=="t5-required-workflows").id')
[ -n "$RS" ] && gh api -X DELETE orgs/OperationCode/rulesets/$RS
NR=$(gh api repos/$R/rulesets --jq '.[]|select(.name=="t5-name-control").id')
[ -n "$NR" ] && gh api -X DELETE repos/$R/rulesets/$NR
gh api orgs/OperationCode/rulesets --jq '.[].name'             # check: no t5 ruleset
gh api repos/$R/rulesets --jq '.[].name'                       # check: no t5-name-control
gh variable delete T5_GATE --repo $R
gh variable delete T5_CALL_GATE --repo $R
gh api -X PUT repos/$R/rulesets/25791558 -f enforcement=active # restore require-scn
gh api repos/$R/rulesets/25791558 --jq .enforcement            # expect: active
for n in <A> <C> <D> <E>; do gh pr close $n --repo $R --delete-branch || true; done   # fork branch of D stays until the fork is deleted
gh workflow disable t5-required.yml --repo $R
gh workflow disable t5-required-call.yml --repo $R
gh workflow disable t5-callee.yml --repo $R
gh repo delete irvingpop/claude-review-test --yes              # needs delete_repo scope; or use the UI
```

If a ruleset cannot be deleted by API: Org settings, Rules, Rulesets, `t5-required-workflows`, Delete; for the repo ruleset, Repo settings, Rules, `t5-name-control`, Delete.

Cleanup does not revert the test files merged to `main`; it only disables the workflows. Optional: a revert PR (no gate after the rules are deleted). PR #4 stays open.

## Fail-safe notes

- The org ruleset is `active` and applies to `claude-review-test` only. It blocks direct pushes to `main`: use PRs.
- `OrganizationAdmin` can bypass on a PR. Do not bypass during the test.
- Never leave `T5_GATE` unset on a real gate: unset means success (fail-open). Test code only.
- Do not merge PRs C, D, E. They hold forged gates.
