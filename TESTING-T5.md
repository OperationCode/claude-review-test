# Test T5: org ruleset rule "Require workflows to pass before merging"

Local design. Nothing here is pushed. The owner (`irvingpop`, org admin) runs every step. No second account is needed: the owner forks the repo to the owner account.

## Questions

| Q | Question |
|---|----------|
| Q2 | Does the org workflows rule ignore a same-name job from a fork PR's own workflow? The plan ends with YES or NO. A plain required-status-check rule is the positive control (it must NOT ignore the job). |
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
 test-fixtures/t5-forgery-fail.yml  forged "t5-gate", always fails (copied over t5-forgery.yml)
 test-fixtures/t5-forgery-edit.yml  same-path edit of t5-required.yml, always fails
 repo ruleset "t5-name-control"     plain required status check "t5-gate" (name-bound control)
```

PRs: A = same-repo, no forgery (control). C = same-repo forgery. D = fork forgery. E = same-path edit. PR #4 (kylemh, outsider fork) is read-only.

The required file lives in `claude-review-test` itself, so it also runs as a NORMAL `pull_request_target` workflow. Keep that normal workflow DISABLED (`gh workflow disable t5-required.yml`) in every row except K2 and C3. Then the only `t5-gate` runs on a head are the ruleset run (Checks tab marks it "Required", path `t5-required.yml`) and the forged run (path `t5-forgery.yml`, event `pull_request`).

Scope: owner-made fork PRs do not exercise the outsider approval gate (`first_time_contributors`). A different-repo same-path attack is not tested. Both are follow-ups.

## Rules for every row

1. Fresh head SHA per row. Set the variables FIRST, then run `bump` (empty commit) or `swap` (changes the forged file), both push to the PR branch. Do not close and reopen: that keeps the old SHA and its old runs. Always `git add <path>`, never `-A`: the `results-T5*` files in the repo dir must not be committed.
2. A row reads only runs of its own head SHA (`rd` below prints them).
3. Wait until every check run of the head is `completed`, then call `rd` twice (it waits 10 seconds).
4. A row is VALID only when `rd` shows the runs in its "Valid if" column. If not, mark the row invalid and rerun it (new `bump`). Never read the merge box of an invalid row.

```sh
cd /Users/irving/src/operationcode/claude-review-test
R=OperationCode/claude-review-test
# bump <branch> <label> <remote>   remote: git@github.com:$R.git, or "fork" for PR D
bump() { git switch -q "$1" && git commit --allow-empty -qm "t5 $2" && git push -q "$3" "$1"; }
# swap <branch> <fixture> <remote>   put test-fixtures/<fixture> at .github/workflows/t5-forgery.yml
swap() { git switch -q "$1" && cp "test-fixtures/$2" .github/workflows/t5-forgery.yml &&
  git add .github/workflows/t5-forgery.yml && git commit -qm "t5 $2" && git push -q "$3" "$1"; }
# rd <pr>   merge box + every check run and workflow run of the current head
rd() { sleep 10; H=$(gh pr view "$1" --repo $R --json headRefOid --jq .headRefOid)
  echo "PR $1 head ${H:0:7}"; gh pr view "$1" --repo $R --json mergeStateStatus --jq .mergeStateStatus
  gh api repos/$R/commits/$H/check-runs --jq '.check_runs[]|[.name,.status,.conclusion,.id]|@tsv'
  gh api "repos/$R/actions/runs?head_sha=$H" --jq '.workflow_runs[]|[.path,.event,.status,.conclusion,.id]|@tsv'; }
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
| 0.8 | PR A: `git switch -c t5-ctrl main`, add a line to `README.md`, `git add README.md && git commit -m "t5 ctrl"`, push, `gh pr create --repo $R --base main --head t5-ctrl --title "t5 control" --body "T5 control"` | note number |
| 0.9 | PR C: `git switch -c t5-forge-same main; mkdir -p .github/workflows; cp test-fixtures/t5-forgery.yml .github/workflows/; git add .github/workflows/t5-forgery.yml && git commit -m "t5 forge"`, push, open PR (`--head t5-forge-same`) | forgery file only |
| 0.10 | PR D: `gh repo fork $R --clone=false; git remote add fork git@github.com:irvingpop/claude-review-test.git`. Sync the fork (`gh repo sync irvingpop/claude-review-test`). `git switch -c t5-forge-fork main`, copy the same file, `git add .github/workflows/t5-forgery.yml && git commit -m "t5 forge"`, `git push fork t5-forge-fork`, `gh pr create --repo $R --base main --head irvingpop:t5-forge-fork --title "t5 forgery fork" --body "T5 Q2"` | forgery file only |
| 0.11 | `gh api orgs/OperationCode/rulesets` | no `t5` ruleset yet |

Fork PR runs can wait for approval: the owner needs none. If a run shows "Approve and run", write it down and do not approve.

## Phase K. Q2 (a): plain required-status-check rule (org ruleset not created yet)

```sh
gh api -X POST repos/$R/rulesets --input test-fixtures/ruleset/t5-repo-name-control.json   # note id as $NR
```

| # | Real `t5-gate` | Setup, then push to C and D | Valid if (`rd`, per head) | Expected | Meaning |
|---|---|---|---|---|---|
| K1 | absent (normal workflow disabled) | `bump` | one `t5-gate`: forged run, `success` | `CLEAN` | CONTROL: a forged pass satisfies a name rule |
| K2 | fail | `gh workflow enable t5-required.yml --repo $R`, `T5_GATE=failure`, `bump` | two `t5-gate`: `t5-required.yml` (`pull_request_target`) `failure`, forged `success` | record only | not used in the decision |
| K3 | absent | `gh workflow disable t5-required.yml --repo $R`, `T5_GATE=success`, `swap <branch> t5-forgery-fail.yml <remote>` | one `t5-gate`: forged run, `failure` | `BLOCKED` | CONTROL: a forged fail blocks a name rule |

If K1 is `BLOCKED` or K3 is `CLEAN` (valid rows), the fixture does not work: stop and fix. Then: `gh api -X DELETE repos/$R/rulesets/$NR`. C and D keep the FAIL fixture for W3.

## Phase W. Q1 and Q2 (b): org workflows rule

```sh
gh api -X POST orgs/OperationCode/rulesets --input test-fixtures/ruleset/t5-org-ruleset.json   # HTTP 201, note id as $RS
gh api orgs/OperationCode/rulesets/$RS --jq '.conditions,.rules'   # include = ["claude-review-test"] only
```

If the POST returns 422 or 403 on the `workflows` rule: stop, record the exact status and text, do not assume the cause. The normal workflow stays disabled.

"Required run" = the `t5-required.yml` run on the head (the normal workflow is off, so it is the ruleset run).

| # | Required run | Setup, then push | PR | Valid if (`rd`, per head) | Expected | Meaning |
|---|---|---|---|---|---|---|
| W0 | pass | `T5_GATE=success`, `bump` | A | Required run `success`, no approval click | `CLEAN` | Q1 sanity. Record `gh api repos/$R/actions/runs/<id> --jq '{event,path,name}'` of the Required run. If no run starts, the ruleset run depends on the normal workflow: record, mark all W rows confounded. |
| W0b | fail | `T5_GATE=failure`, `bump` | A | Required run `failure` | `BLOCKED` | Q1: the result gates the merge |
| W3 | pass, forged FAIL | `T5_GATE=success`, `bump` (fail fixture still in place from K3) | C, D | Required run `success` AND forged run `failure` | see Decision | Q2: does a forged fail block? |
| W1 | fail, forged PASS | `T5_GATE=failure`, `swap <branch> t5-forgery.yml <remote>` | C, D | Required run `failure` AND forged run `success` | see Decision | Q2: does a forged pass satisfy? |
| W2 | outsider fork | `T5_GATE=success`; close and reopen PR #4 (closing a third-party PR is intended; it is reopened at once) | #4 | none | record only | Q1 outsider: run starts? approval needed? |

If W0 is not `CLEAN` or W0b is not `BLOCKED`, the workflows rule does not gate: stop, Q2 cannot be read.

## Decision (Q2)

Only valid rows count (rule 4). PR D (fork) decides Q2. PR C (same repo) is recorded; if it differs from D, write it down as a separate finding.

Preconditions: K1 `CLEAN`, K3 `BLOCKED`, W0 `CLEAN`, W0b `BLOCKED`. If one fails, fix and rerun that row; do not answer Q2 yet.

| W1 (D) | W3 (D) | Answer: does the workflows rule ignore the fork's same-name job? |
|---|---|---|
| `BLOCKED` | `CLEAN` | YES. A forged pass does not satisfy it and a forged fail does not block it. |
| `CLEAN` | any | NO. A forged pass satisfies the rule. The reviewer gate cannot rely on it alone. |
| any | `BLOCKED` | NO. The forged job counts for the rule (the Required run passed, and no other rule is active). |

All four outcomes give YES or NO. The rows cannot be confused: W1 and W3 have only one failed run each, and K3 proves the forged run is visible to a rule.

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
| C3 | `PUT` the original `t5-org-ruleset.json` back. `T5_GATE=success`. `gh workflow enable t5-required.yml --repo $R` (else the PR copy cannot run). PR E: `git switch -c t5-edit main; cp test-fixtures/t5-forgery-edit.yml .github/workflows/t5-required.yml; git add .github/workflows/t5-required.yml && git commit -m "t5 edit"`, push, open PR. After `rd`: `gh workflow disable t5-required.yml --repo $R`. | Valid if three `t5-required.yml` runs: PR copy (`pull_request`, summary `edited-by-pr`) `failure`; normal base run (`pull_request_target`) `success`; Required run (event as in W0) `success`. `CLEAN`: the PR copy does not affect the rule. `BLOCKED`: the PR copy counts (finding; the only failed run is the PR copy). |

Q4 pin is YES when C1 is 200 and C2 shows `v1`. Q4 edit is YES (ignored) when C3 is `CLEAN`.

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
gh api repos/$R/rulesets --jq '.[].name'                       # check: no t5-name-control (also lists org rulesets: t5-required-workflows here means the org delete failed)
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
