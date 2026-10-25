# Test T5: org ruleset rule "Require workflows to pass before merging"

Local design. Nothing here is pushed. The owner (`irvingpop`, org admin) runs every step. No second account is needed: the owner forks the repo to the owner account.

## Questions

| Q | Question |
|---|----------|
| Q1 | Does an org ruleset (workflows rule, target only `claude-review-test`) run the required workflow (`pull_request_target`) on same-repo and fork PRs, and does its result block or allow the merge? |
| Q2 | Is the workflows rule bound to the WORKFLOW or only to the job NAME? A PR adds its own `on: pull_request` workflow with a job named like the required job. Test with a name-bound control (plain required-status-check rule on `t5-gate`) and the workflows rule, in matched job states, on a fork PR and a same-repo PR. |
| Q3 | Can the required workflow read the PR number and call a reusable workflow (`workflow_call`)? |
| Q4 | Does the ruleset accept a pinned `sha`? What happens when a PR edits the workflow at the same path in the target repo (PR copy runs on `pull_request`)? |

## Design

```
 org ruleset "t5-required-workflows"  (target: claude-review-test only, default branch)
   rule: workflows  ->  repository_id 1432457406 (claude-review-test itself)
                        path .github/workflows/t5-required.yml  @ refs/heads/main
                        (phase B adds t5-required-call.yml, phase C pins a sha)

 t5-required.yml       job "t5-gate"      result = repo variable T5_GATE
 t5-required-call.yml  job "t5-call"  ->  t5-callee.yml (workflow_call)
                                          result = repo variable T5_CALL_GATE
 test-fixtures/t5-forgery.yml       forged job "t5-gate" (always passes)
 test-fixtures/t5-forgery-edit.yml  same-path edit of t5-required.yml (pull_request, always passes)
 repo ruleset "t5-name-control"     plain required status check "t5-gate" (name-bound control)
```

Real job states for Q2 (repo variables on the real `t5-gate`): `fail` = `T5_GATE=failure`; `pending` = `T5_SLEEP=300` (read while the job runs); `skipped` = `T5_SKIP=true`; `absent` = normal workflow disabled (name-bound control only).

Where the required workflow lives: in `claude-review-test` itself. Reasons: no PR approval in `OperationCode/.github`, no test file in the production repo, and no deadlock if the file reaches `main` before the ruleset exists. Limits of this choice are in the report (`report-T5-design.md`): the file also runs as a normal workflow (confounder, see below), and a different-repo same-path attack is not tested.

Confounder: with source repo = target repo, `t5-required.yml` also runs as a NORMAL `pull_request_target` workflow, so a PR can show two runs named `t5-gate`. Rules to tell them apart:
- The Checks tab marks the ruleset run "Required". Record that run id and its `gh api repos/$R/actions/runs/<id> --jq '{event,path,name,workflow_id}'`. Diff it against the normal run.
- Step A3b disables the normal workflow BEFORE any Q1 or Q2 (workflows rule) read. A run that still starts on a new PR event is the ruleset run. If A3b shows that disabling the file also stops the ruleset run, write that down (it is a finding), re-enable, and mark Q1 and Q2 as read with the confounder.

Scope notes: `fork-pr-contributor-approval` is `first_time_contributors` and the owner is an org admin, so an OUTSIDER fork approval gate is not exercised by owner-made fork PRs (D, F). PR #4 (kylemh) is a real outside-contributor fork PR: use it for the Q1 read and record whether its run needed approval. Q2 covers job substitution only, not the "outsider run waits for approval, real job absent" path. Open PRs #2, #3, #5, #6, #7 (same repo) also fall under the active org rule and get blocked when they next get an event. Cleanup does not touch them.

Read the real check names in the merge box. This plan uses the job names (`t5-gate`, `t5-call`, `callee-gate`). A required workflow can show a longer name. Write down what you see.

## Variables and commands

```sh
cd /Users/irving/src/operationcode/claude-review-test
R=OperationCode/claude-review-test
# merge box state of PR N:
gh pr view N --repo $R --json mergeStateStatus,mergeable,statusCheckRollup
# runs of the head: 
gh run list --repo $R --limit 10 --json databaseId,name,event,status,conclusion,headSha,workflowName
```

`mergeStateStatus` is the merge box. `CLEAN` = can merge. `BLOCKED` = a required rule is not met. Do not use `statusCheckRollup.state` as the gate (T4 showed it can differ). As org admin you see a bypass option on a BLOCKED PR. The bypass option does not change `mergeStateStatus`. Do not use it.

Wait until every run of a step has finished before you read the state. Read twice, 10 seconds apart.

## Phase 0. Setup (owner)

| # | Action | Expected |
|---|--------|----------|
| 0.1 | `gh auth refresh -h github.com -s admin:org` | token can read and write org rulesets |
| 0.2 | Save the repo ruleset: `gh api repos/$R/rulesets/25791558 > /Users/irving/src/operationcode/claude-review-test/results-T5-require-scn.json` | file saved (inside the repo dir, do not commit it) |
| 0.3 | Disable the repo ruleset `require-scn`: `gh api -X PUT repos/$R/rulesets/25791558 -f enforcement=disabled` | `enforcement: disabled`. Only the org rule must gate during T5. |
| 0.4 | Push branch `t5-required-workflows` over SSH (`git push git@github.com:$R.git t5-required-workflows`). Open a PR to `main` and merge it. | `main` has the 3 workflow files and `test-fixtures/`. Over HTTPS the push needs the `workflow` token scope. |
| 0.5 | `git switch main && git pull`, then `S1=$(git rev-parse HEAD)` and keep `$S1`. | `S1` is the commit where `WORKFLOW_VERSION: v1` |
| 0.6 | `gh variable set T5_GATE --repo $R --body success` and `gh variable set T5_CALL_GATE --repo $R --body success` | 2 variables |
| 0.7 | Record the ruleset list: `gh api orgs/OperationCode/rulesets` | no `t5` ruleset yet |
| 0.8 | Create a same-repo control branch: `git switch -c t5-ctrl main`, add one line to `README.md`, `git push git@github.com:$R.git t5-ctrl`, `gh pr create --repo $R --base main --head t5-ctrl --title "t5 control" --body "T5 control"` | PR "A" (same-repo). Note its number. |

Fork PR "B" is existing PR #4 (author `kylemh`).

## Phase A. Q1 (gate only)

| # | Action | Expected | Read |
|---|--------|----------|------|
| A1 | Create the ruleset: `gh api -X POST orgs/OperationCode/rulesets --input test-fixtures/ruleset/t5-org-ruleset.json` (copy in `test-fixtures/ruleset/`). Keep the `id` as `$RS`. | HTTP 201. If 422 or 403 on the `workflows` rule: stop and record the exact status and error text. Do not assume the cause (plan limit, permission, schema). | response body |
| A2 | Check: `gh api orgs/OperationCode/rulesets/$RS --jq '.conditions,.rules'` | `repository_name.include = ["claude-review-test"]` only. Rule has `repository_id 1432457406`. | JSON |
| A3 | PR A and PR B were open before the rule. Run `gh pr close N` then `gh pr reopen N` for each. | New run of `t5-required` (event `pull_request_target`, action `reopened`) per PR. Note: the file is also a normal workflow in this repo, so you can see TWO runs per PR (one normal, one from the ruleset). Write down both (run id, `path`, check name). | `gh run list`, Checks tab |
| A3b | `gh workflow disable t5-required.yml --repo $R`, then close and reopen A and B. | Confounder control. Does the ruleset run still start? Only that run exists now (event, path, check name). Keep the normal workflow disabled for A4 to A8 and for phase A2. | `gh run list`, Checks tab |
| A4 | Read the merge box of A and B. T5_GATE is `success`. | `CLEAN` (or `UNSTABLE`, if other unrelated checks fail). Required check listed as required. | `gh pr view` |
| A5 | `gh variable set T5_GATE --repo $R --body failure`, then close and reopen A. Then B. | Run fails. `BLOCKED` for A and B. | `gh pr view` |
| A6 | `gh variable set T5_GATE --repo $R --body success`, close and reopen A and B. | `CLEAN` again. Gate follows the newest result. | `gh pr view` |
| A7 | Push a new commit to `t5-ctrl` (synchronize event). Set `T5_GATE=failure` first. | New run, `BLOCKED`. Shows `synchronize` is covered. | `gh pr view` |
| A8 | `gh api orgs/OperationCode/rulesets/rule-suites --jq '.[0:5]'` | rule suite evaluation records for the PRs (optional) | JSON |

Q1 is answered YES when: the run marked "Required" starts on both PRs (also with the normal workflow disabled, A3b) without any approval click, and BLOCKED/CLEAN follows `T5_GATE`. Write down any approval prompt on PR B (#4, outside contributor). Q1 says "owner fork PR" only for D and F.

## Phase K. Q2 control: name-bound rule (run BEFORE phase A2)

Purpose: show that a same-name job DOES satisfy a plain required-status-check rule, so a `BLOCKED` in phase A2 means something. Org workflows rule is off here; only the name-bound rule gates.

Create the forgery PRs C (same-repo) and D (fork) first (commands in phase A2). Then:

```sh
gh api -X PUT orgs/OperationCode/rulesets/$RS -f enforcement=disabled                  # org workflows rule off
gh api -X POST repos/$R/rulesets --input test-fixtures/ruleset/t5-repo-name-control.json   # keep id as $NR
gh workflow enable t5-required.yml --repo $R                                           # real job runs normally
```

Matched states. For each row set the variables, close and reopen the PR, wait, read the merge box twice, 10 s apart. For `pending`, read while the real run is still in progress and the forged run has finished.

| # | State of real `t5-gate` | Variables | PR | Expected (name-bound) | Meaning |
|---|---|---|---|---|---|
| K1 | pass, no forgery | `T5_GATE=success` | A | `CLEAN` | sanity: the rule is satisfiable |
| K2 | absent, no forgery | `gh workflow disable t5-required.yml`, PR A reopen | A | `BLOCKED` (expected check missing) | sanity: absence blocks |
| K3 | absent, forged pass | normal workflow still disabled | C, D | `CLEAN` | POSITIVE CONTROL: forgery by name works in this repo. Needs `CLEAN` on C and D. If `BLOCKED`, the forgery fixture does not work; stop and fix before A2. |
| K4 | fail, forged pass | `gh workflow enable ...`, `T5_GATE=failure` | C, D | record (`BLOCKED` or `CLEAN`) | does a mixed fail+pass under one name block? Decides whether A2 row S-fail can discriminate. |
| K5 | pending, forged pass | `T5_GATE=success`, `T5_SLEEP=300` | C, D | record | name-bound result with the real job in progress |
| K6 | skipped, forged pass | `T5_SLEEP` deleted, `T5_SKIP=true` | C, D | record | skipped job and forged pass under one name |
| K7 | skipped, no forgery | `T5_SKIP=true` | A | record | does a skipped real job alone satisfy a name-bound rule (docs say skipped counts as success) |

Then restore: `gh variable delete T5_SLEEP --repo $R; gh variable delete T5_SKIP --repo $R; gh workflow enable t5-required.yml --repo $R`, then `gh api -X DELETE repos/$R/rulesets/$NR`, then `gh api -X PUT orgs/OperationCode/rulesets/$RS -f enforcement=active`, then `gh workflow disable t5-required.yml --repo $R` (normal run off again for phase A2).

## Phase A2. Q2 forgery against the workflows rule (normal workflow disabled, A3b)

Org ruleset `active`, repo rule `t5-name-control` deleted. Same states as phase K, so every row pairs with a K row.

Same-repo forgery (owner, PR "C"), skip if it exists from phase K:

```sh
git switch -c t5-forge-same main
mkdir -p .github/workflows
cp test-fixtures/t5-forgery.yml .github/workflows/t5-forgery.yml
git add .github/workflows/t5-forgery.yml && git commit -m "t5 forgery same-repo"
git push git@github.com:$R.git t5-forge-same
gh pr create --repo $R --base main --head t5-forge-same --title "t5 forgery same-repo" --body "T5 Q2"
```

Fork forgery (owner forks to the owner account, PR "D"), skip if it exists from phase K:

```sh
gh repo fork $R --clone=false          # creates irvingpop/claude-review-test
git remote add fork git@github.com:irvingpop/claude-review-test.git
git switch -c t5-forge-fork main
mkdir -p .github/workflows
cp test-fixtures/t5-forgery.yml .github/workflows/t5-forgery.yml
git add .github/workflows/t5-forgery.yml && git commit -m "t5 forgery fork"
git push fork t5-forge-fork
gh pr create --repo $R --base main --head irvingpop:t5-forge-fork --title "t5 forgery fork" --body "T5 Q2"
```

The forgery branch adds exactly one file: `.github/workflows/t5-forgery.yml` (copy of `test-fixtures/t5-forgery.yml`). If the fork is older than the merge of step 0.4, sync it first (`gh repo sync irvingpop/claude-review-test`).

| # | State of real (ruleset) `t5-gate` | Variables | PR | Expected (workflow-bound) | Pairs with |
|---|---|---|---|---|---|
| F1 | fail, forged pass | `T5_GATE=failure` | C, D | `BLOCKED` | K4 |
| F2 | pending, forged pass | `T5_GATE=success`, `T5_SLEEP=300` | C, D | `BLOCKED` while the ruleset run is in progress | K5 |
| F3 | skipped, forged pass | `T5_SLEEP` deleted, `T5_SKIP=true` | C, D | record | K6 |
| F4 | skipped, no forgery | `T5_SKIP=true` | A | record | K7 |
| F5 | pass, forged pass | `T5_SKIP` deleted, `T5_GATE=success` | C, D | `CLEAN` (a forged job does not break a good PR) | K1 |
| F6 | fail, forged pass, after a new commit | `T5_GATE=failure`, push a commit to each forgery branch | C, D | `BLOCKED` stays | K4 |

Read both runs by name: Checks tab lists the real run (marked "Required") and the forged run (event `pull_request`) both as `t5-gate`. Fork PR runs can wait for approval: the owner needs none; if a run shows "Approve and run", write it down and do not approve.

Decision (binding proof): the rule is bound to the WORKFLOW (not the name) when, for some state S, the K row is `CLEAN` and the matching F row is `BLOCKED`. Readings:
- K3 `CLEAN` is required first (forgery works by name). Without it nothing below counts.
- K4 `CLEAN` and F1 `BLOCKED`: fail+forged discriminates, binding is to the workflow.
- K4 `BLOCKED`: F1 proves nothing (both block). Use the K5/F2 pair: K5 `CLEAN` and F2 `BLOCKED` proves it.
- Any F row `CLEAN` where the real run did not pass (F2, F3): the forgery works against the workflows rule too. Record as a finding.
- F4 `CLEAN`: a skippable real job lets any PR through. Gate jobs must never be skippable.
- No state discriminates: Q2 stays open. Do not claim either result.

## Phase B. Q3 (reusable workflow)

| # | Action | Expected | Read |
|---|--------|----------|------|
| B1 | `gh api -X PUT orgs/OperationCode/rulesets/$RS --input test-fixtures/ruleset/t5-org-ruleset-phaseB.json` | HTTP 200, 2 workflows in the rule | response |
| B2 | `T5_GATE=success`, `T5_CALL_GATE=success`. Close and reopen A. | Run `t5-required-call` starts. Job `t5-call` calls `t5-callee`. | `gh run list` |
| B3 | Open the run summary of `t5-callee`. | `input pr_number` and `github.event pr number` both equal the PR number. `workflow_ref` shows the caller or the callee: write it down. | Summary page |
| B4 | `T5_CALL_GATE=failure`, close and reopen A. | `BLOCKED` by the call workflow alone (T5_GATE is success) | `gh pr view` |
| B5 | `T5_CALL_GATE=success`, close and reopen A. | `CLEAN` | `gh pr view` |
| B6 | Repeat B2 and B4 on fork PR D. | Same result as A. If the call fails to start (access error), write the exact message. | `gh pr view` |

Q3 is answered YES when B3 shows the number and B4 blocks. If B2 never starts a run: a required workflow cannot use `workflow_call` (or needs a setting). Then the design must be self-contained.

## Phase C. Q4 (pinned sha, same-path edit)

| # | Action | Expected | Read |
|---|--------|----------|------|
| C1 | Edit `test-fixtures/ruleset/t5-org-ruleset-phaseC-sha.json`: replace `REPLACE_WITH_40_CHAR_COMMIT_SHA` with `$S1`. `gh api -X PUT orgs/OperationCode/rulesets/$RS --input test-fixtures/ruleset/t5-org-ruleset-phaseC-sha.json` | HTTP 200 and the response echoes `sha`. If 422 on `sha` without `ref`: record the text, retry with `"ref": "refs/heads/main"` and `sha` together. | response |
| C2 | Close and reopen A. Read the `t5-required` summary. | `workflow_sha` equals `$S1`, `version: v1` | summary |
| C3 | Advance `main`: branch `t5-v2` from `main`, change `WORKFLOW_VERSION: v1` to `v2` in `.github/workflows/t5-required.yml`. Set `T5_GATE=success`. Push, open PR, merge it. | `main` moves to `S2` | git |
| C4 | Close and reopen A. | The ruleset still runs `v1`, `workflow_sha` = `$S1` (the pin holds). A normal run from `main` shows `v2`. | summary of both runs |
| C5 | Put phase A back: `PUT ... --input test-fixtures/ruleset/t5-org-ruleset.json`. Close and reopen A. | the ruleset run now shows `v2` (ref follows `main`) | summary |
| C6 | Same-path edit, same repo. Run `gh workflow enable t5-required.yml --repo $R` first (the PR copy needs the path enabled; if it still does not run, note that). Set `T5_GATE=failure`, `T5_SLEEP` and `T5_SKIP` deleted. `git switch -c t5-edit main && cp test-fixtures/t5-forgery-edit.yml .github/workflows/t5-required.yml`, commit, push, open PR "E". | Runs on the head: (1) PR copy, event `pull_request`, summary `edited-by-pr`, PASSES; (2) normal run from `main`, event `pull_request_target`, FAILS; (3) ruleset run (Required), version from ruleset ref, FAILS. Merge box `BLOCKED`. Write down every run with event and workflow_ref. | `gh pr view`, runs, summaries |
| C7 | Same-path edit, fork. In the fork: `git switch -c t5-edit-fork main`, same copy, `git push fork t5-edit-fork`, PR "F" with `--head irvingpop:t5-edit-fork`. | Same as C6: `BLOCKED` | `gh pr view` |
| C8 | Repeat C6 with the normal workflow disabled (`gh workflow disable t5-required.yml --repo $R`), reopen E. | Does the PR copy still run? Does the ruleset run still start? Write down both. Then enable the workflow again. | `gh pr view`, runs |

Q4 is answered YES (pin accepted) when C1 is 200 and C4 shows `v1`. Same-path edit is harmless when C6 and C7 stay `BLOCKED` while the PR copy (event `pull_request`) is green. If the merge box is `CLEAN`, the PR copy replaced the required run: record as a finding.

## Evidence to save

For each step: the `gh pr view` JSON, the run ids, the check names as shown, the HTTP status and body of each ruleset call. Save to `/Users/irving/src/operationcode/claude-review-test/results-T5.md` (do not commit secrets; there are none).

## Cleanup

If the test stops at ANY phase, run the first 2 lines (plus the `$NR` delete if phase K was started) first.

```sh
gh api -X DELETE orgs/OperationCode/rulesets/$RS              # delete the org ruleset
gh api orgs/OperationCode/rulesets                             # check: no t5 ruleset
gh api -X DELETE repos/$R/rulesets/$NR || true                 # name-bound control, if it exists
gh api repos/$R/rulesets --jq '.[].name'                       # check: no t5-name-control
gh variable delete T5_GATE --repo $R
gh variable delete T5_CALL_GATE --repo $R
gh variable delete T5_SLEEP --repo $R || true
gh variable delete T5_SKIP --repo $R || true
gh api -X PUT repos/$R/rulesets/25791558 -f enforcement=active # restore require-scn
gh api repos/$R/rulesets/25791558 --jq .enforcement            # expect: active
for n in <A> <C> <D> <E> <F>; do gh pr close $n --repo $R --delete-branch || true; done   # fork branches (D, F) cannot be deleted here: error is harmless
gh workflow disable t5-required.yml --repo $R
gh workflow disable t5-required-call.yml --repo $R
gh workflow disable t5-callee.yml --repo $R
gh repo delete irvingpop/claude-review-test --yes              # needs delete_repo scope; or use the UI
```

Cleanup does NOT revert the test files merged to `main` in step 0.4; it only disables the workflows. To remove them, open a revert PR (the org rule is deleted by then, so no gate). Optional.

PR #4 (kylemh) stays open. Branch `t5-forge-fork` and `t5-edit-fork` vanish with the fork. If the org ruleset cannot be deleted by API, use Org settings, Rules, Rulesets, `t5-required-workflows`, Delete.

## Fail-safe notes

- The org ruleset is `active` and applies to `claude-review-test` only. It blocks direct pushes to `main`: use PRs.
- OrganizationAdmin can bypass on a PR. Do not bypass during the test.
- Never leave `T5_GATE` unset on a real gate: unset means success (fail-open). This is test code only.
