# Test T5: org ruleset rule "Require workflows to pass before merging"

Local design. Nothing here is pushed. The owner (`irvingpop`, org admin) runs every step. No second account is needed: the owner forks the repo to the owner account.

## Questions

| Q | Question |
|---|----------|
| Q1 | Does an org ruleset (workflows rule, target only `claude-review-test`) run the required workflow (`pull_request_target`) on same-repo and fork PRs, and does its result block or allow the merge? |
| Q2 | Forgery: a PR adds its own `on: pull_request` workflow with a job named like the required job, and that job passes while the required workflow fails. Does the merge box stay BLOCKED? Test with a fork PR and a same-repo PR. |
| Q3 | Can the required workflow read the PR number and call a reusable workflow (`workflow_call`)? |
| Q4 | Does the ruleset accept a pinned `sha`? What happens when a PR edits the workflow at the same path in the target repo? |

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
 test-fixtures/t5-forgery-edit.yml  same-path edit of t5-required.yml (always passes)
```

Where the required workflow lives: in `claude-review-test` itself. Reasons: no PR approval in `OperationCode/.github`, no test file in the production repo, and no deadlock if the file reaches `main` before the ruleset exists. Limits of this choice are in the report (`report-T5-design.md`): the file also runs as a normal workflow, and a different-repo same-path attack is not tested.

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
| 0.2 | Save the repo ruleset: `gh api repos/$R/rulesets/25791558 > /tmp/require-scn.json` | file saved |
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
| A1 | Create the ruleset: `gh api -X POST orgs/OperationCode/rulesets --input test-fixtures/ruleset/t5-org-ruleset.json` (copy in `test-fixtures/ruleset/`). Keep the `id` as `$RS`. | HTTP 201. If 422 or 403 on the `workflows` rule: Team plan does not allow it. Stop. Record the exact error. | response body |
| A2 | Check: `gh api orgs/OperationCode/rulesets/$RS --jq '.conditions,.rules'` | `repository_name.include = ["claude-review-test"]` only. Rule has `repository_id 1432457406`. | JSON |
| A3 | PR A and PR B were open before the rule. Run `gh pr close N` then `gh pr reopen N` for each. | New run of `t5-required` (event `pull_request_target`, action `reopened`) per PR. Note: the file is also a normal workflow in this repo, so you can see TWO runs per PR (one normal, one from the ruleset). Write down both (run id, `path`, check name). | `gh run list`, Checks tab |
| A4 | Read the merge box of A and B. T5_GATE is `success`. | `CLEAN` (or `UNSTABLE`, if other unrelated checks fail). Required check listed as required. | `gh pr view` |
| A5 | `gh variable set T5_GATE --repo $R --body failure`, then close and reopen A. Then B. | Run fails. `BLOCKED` for A and B. | `gh pr view` |
| A6 | `gh variable set T5_GATE --repo $R --body success`, close and reopen A and B. | `CLEAN` again. Gate follows the newest result. | `gh pr view` |
| A7 | Push a new commit to `t5-ctrl` (synchronize event). Set `T5_GATE=failure` first. | New run, `BLOCKED`. Shows `synchronize` is covered. | `gh pr view` |
| A8 | `gh api orgs/OperationCode/rulesets/rule-suites --jq '.[0:5]'` | rule suite evaluation records for the PRs (optional) | JSON |

Q1 is answered YES when: the required run starts on both PRs without any approval click, and BLOCKED/CLEAN follows `T5_GATE`. Write down any approval prompt on PR B.

## Phase A2. Q2 forgery (gate still `failure`)

Set `gh variable set T5_GATE --repo $R --body failure`.

Same-repo forgery (owner, PR "C"):

```sh
git switch -c t5-forge-same main
mkdir -p .github/workflows
cp test-fixtures/t5-forgery.yml .github/workflows/t5-forgery.yml
git add .github/workflows/t5-forgery.yml && git commit -m "t5 forgery same-repo"
git push git@github.com:$R.git t5-forge-same
gh pr create --repo $R --base main --head t5-forge-same --title "t5 forgery same-repo" --body "T5 Q2"
```

Fork forgery (owner forks to the owner account, PR "D"):

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

The fork branch adds exactly one file: `.github/workflows/t5-forgery.yml` (copy of `test-fixtures/t5-forgery.yml`). If the fork is older than the merge of step 0.4, sync it first (`gh repo sync irvingpop/claude-review-test`).

| # | Action | Expected | Read |
|---|--------|----------|------|
| F1 | Wait for all runs on C and D. | Required `t5-required / t5-gate` fails. Forged `t5-gate` (event `pull_request`) passes. The Checks tab lists both under the name `t5-gate`. | Checks tab, `gh run list` |
| F2 | Read the merge box of C and D. | PASS of the test = `BLOCKED` on both. FAIL = `CLEAN` or `UNSTABLE` on either: the forgery works and the gate is NOT bound to the workflow. | `gh pr view` |
| F3 | The fork run can wait for approval. The owner needs none. If the run shows "Approve and run", note it. Do not approve for an outsider test. | note | Actions tab |
| F4 | Push one more commit to each forgery branch (synchronize). Read again. | `BLOCKED` stays | `gh pr view` |
| F5 | Control: `T5_GATE=success`, close and reopen C and D. | `CLEAN`. Shows a forged job does not break a good PR. | `gh pr view` |
| F6 | Optional name-binding contrast: turn the repo ruleset `require-scn` back on is NOT useful (other name). Skip unless you want a status-check rule on `t5-gate`; then forgery should clear it. | n/a | n/a |

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
| C6 | Same-path edit, same repo. Set `T5_GATE=failure`. `git switch -c t5-edit main && cp test-fixtures/t5-forgery-edit.yml .github/workflows/t5-required.yml`, commit, push, open PR "E". | Run from `main` (base) fails: `BLOCKED`. The edited copy does not run for `pull_request_target`. Write down every run on the head. | `gh pr view`, runs |
| C7 | Same-path edit, fork. In the fork: `git switch -c t5-edit-fork main`, same copy, `git push fork t5-edit-fork`, PR "F" with `--head irvingpop:t5-edit-fork`. | Same as C6: `BLOCKED` | `gh pr view` |
| C8 | Optional: `gh workflow disable t5-required.yml --repo $R`, then close and reopen A (gate `failure`). | Write down: does the ruleset run still start and block? Then `gh workflow enable t5-required.yml --repo $R`. | `gh pr view` |

Q4 is answered YES (pin accepted) when C1 is 200 and C4 shows `v1`. Same-path edit is harmless when C6 and C7 stay `BLOCKED`.

## Evidence to save

For each step: the `gh pr view` JSON, the run ids, the check names as shown, the HTTP status and body of each ruleset call. Save to `/Users/irving/src/operationcode/claude-review-test/results-T5.md` (do not commit secrets; there are none).

## Cleanup

```sh
gh api -X DELETE orgs/OperationCode/rulesets/$RS              # delete the org ruleset
gh api orgs/OperationCode/rulesets                             # check: no t5 ruleset
gh variable delete T5_GATE --repo $R
gh variable delete T5_CALL_GATE --repo $R
gh api -X PUT repos/$R/rulesets/25791558 -f enforcement=active # restore require-scn
gh api repos/$R/rulesets/25791558 --jq .enforcement            # expect: active
for n in <A> <C> <D> <E> <F>; do gh pr close $n --repo $R --delete-branch; done
gh workflow disable t5-required.yml --repo $R
gh workflow disable t5-required-call.yml --repo $R
gh workflow disable t5-callee.yml --repo $R
gh repo delete irvingpop/claude-review-test --yes              # needs delete_repo scope; or use the UI
```

PR #4 (kylemh) stays open. Branch `t5-forge-fork` and `t5-edit-fork` vanish with the fork. If the org ruleset cannot be deleted by API, use Org settings, Rules, Rulesets, `t5-required-workflows`, Delete.

## Fail-safe notes

- The org ruleset is `active` and applies to `claude-review-test` only. It blocks direct pushes to `main`: use PRs.
- OrganizationAdmin can bypass on a PR. Do not bypass during the test.
- Never leave `T5_GATE` unset on a real gate: unset means success (fail-open). This is test code only.
