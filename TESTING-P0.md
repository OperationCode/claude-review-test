# Phase 0 test plan

The ten phase 0 items of the [design spec](https://github.com/OperationCode/.github/blob/main/docs/claude-review-design.md) ("Verify before building"): V6 (first), V2, V3, V4, V5, V9, V13, V16, V18, V24. The pass and fail rules below come from the spec. Record each result in the spec, in the same PR as any design change it causes.

Roles: the **owner** (org owner, admin of this repo), a **writer** (a second account with Write on this repo, not an admin), and a **worker** (pushes and PRs in this repo only; a push to the fork `irvingpop/claude-review-test` needs the owner's OK).

## Files

| File | Repo | Used by |
|------|------|---------|
| `.github/workflows/p0-required.yml` | scratch source repo (not this repo) | V6, V2, V4, V3, V9, V24 |
| [.github/workflows/p0-v18-fork-objects.yml](.github/workflows/p0-v18-fork-objects.yml) | this repo | V18 |
| [.github/workflows/p0-v24-run-list.yml](.github/workflows/p0-v24-run-list.yml) | this repo | V24 |
| [.github/workflows/p0-v13-dependency-review.yml](.github/workflows/p0-v13-dependency-review.yml) | this repo | V13 |
| [.github/workflows/p0-v6-token-push.yml](.github/workflows/p0-v6-token-push.yml) | this repo | V6 (c) |
| [.github/workflows/p0-v3-other-repo.yml](.github/workflows/p0-v3-other-repo.yml) | this repo | V3 |
| [test-fixtures/ruleset/p0-org-ruleset.json](test-fixtures/ruleset/p0-org-ruleset.json) | this repo (template) | the test org ruleset |
| [test-fixtures/p0/v13/](test-fixtures/p0/v13) | this repo | V13 (fork PRs copy the `.fixture` files; `safe/` is the control) |
| [test-fixtures/p0/v4/](test-fixtures/p0/v4) | this repo | V4 (`dependabot.yml` is staged, not active) |
| [scripts/p0/observe.sh](scripts/p0/observe.sh) | run locally | V6, V4, V2: merge box, runs and other checks, one JSON line per poll |
| [scripts/p0/v16-check.sh](scripts/p0/v16-check.sh) | run locally | V16: timeline events, push epoch, override verdicts |
| [scripts/p0/readback.sh](scripts/p0/readback.sh) | run locally | ruleset read-back: `repository_id`, path, `sha`, no `ref`, enforcement, bypass, target |
| [scripts/p0/v5-request.sh](scripts/p0/v5-request.sh) | run locally, costs money | V5 |
| [scripts/p0/v9-spend.sh](scripts/p0/v9-spend.sh) | run locally, costs money | V9 |

All workflows: no checkout, no PR content fetched for execution, least token scopes per job, PR text only through `env`. The only action is `actions/dependency-review-action`, pinned by full SHA. The OIDC token is never printed: jobs print decoded claims only.

## The scratch gate (`p0-required.yml`)

Same job graph as the central workflow: `collect` -> `analyze` -> `oc-claude-review` (`if: always()`). Controls are PR comments by an `OWNER`, `MEMBER` or `COLLABORATOR` author:

```
/p0 knobs collect_sleep=<0-150> force=<none|pass|fail|timeout> pause=<0-1500>
/p0 override <40-char head sha>
```

- The newest `/p0 knobs` comment at the start of `collect` applies to that run. Post the knobs for the next run before you start it. Defaults: `collect_sleep=0 force=none pause=0`. A value out of range is ignored (check `collect_sleep` in the `collect` summary).
- `force=none`: the gate fails ("simulated high finding") unless a valid override exists. Valid: exact head SHA, never edited, created strictly after the push epoch.
- `force=pass` passes with no override. `force=fail` fails. `force=timeout` makes `collect` run past its 3 minute timeout.
- `collect_sleep` slows `collect` (in-progress state). The cap of 150 s keeps `collect` inside its 3 minute timeout, so a slow run still completes and reaches the gate. `pause` makes the gate job wait after its final check, with its result already fixed, before it exits. While paused it logs each new run on the head SHA with `delay_min_s` and `delay_max_s` (V24 data).
- Queued state: `collect` runs on the repo variable `P0_COLLECT_RUNS_ON` when it is set (default `ubuntu-latest`). The owner sets it to a label that no runner has, the next run stays `queued`, then the owner deletes the variable and the worker cancels the run (see the V6 matrix).
- The gate fails `superseded` when a run of the same workflow (same `workflow_id` or `path`) with a higher run ID exists on the head SHA at the final check.
- Not the spec gate: no "author is not the PR author" rule, and `author_association` stands in for the permission API.

## Setup (in this order)

The repo ruleset `require-scn` (id 25791558) stays on. It requires the status check `oc-claude-review-scn` on `main` only, and nothing produces that check today (`t4-jobcheck.yml` is disabled). So the plan keeps the ruleset tests off `main`: the test org ruleset covers the branch `p0-base`, and every V6, V2, V3, V4 and V9 PR targets `p0-base`. Merges to `main` are only needed to put `pull_request_target` and `workflow_dispatch` files there (both always use the file on the default branch). For each such merge the owner satisfies `oc-claude-review-scn` on that PR's head.

| Step | Who | Action |
|------|-----|--------|
| S1 | worker, owner | Open a PR `phase0-tests` -> `main`. Owner: post the required status on its head SHA: `gh api -X POST repos/OperationCode/claude-review-test/statuses/<head sha> -f state=success -f context=oc-claude-review-scn -f description="owner: phase 0 kit merge"` (the rule names no source app, so a commit status counts). Worker: merge. This puts the `p0-*` workflows on `main`. Use the same status step for every later merge to `main` (V3 step 3, V4 step 1). |
| S1b | worker | Push branch `p0-base` from `main` after S1 (`git push origin origin/main:refs/heads/p0-base`). `require-scn` targets `main` only, so this push and all PRs to `p0-base` are outside it. |
| S2 | owner | Create a public scratch source repo in the org, for example `OperationCode/claude-review-p0-source`. Push `p0-required.yml` (from the kit) to `.github/workflows/` on `main`. Record the repo id (`gh api repos/OperationCode/<name> --jq .id`) and the commit SHA. |
| S3 | owner | Create the test org ruleset from `test-fixtures/ruleset/p0-org-ruleset.json`: set `repository_id` to the scratch repo id and `sha` to the S2 commit SHA. It targets `refs/heads/p0-base` on this repo only. `gh api -X POST orgs/OperationCode/rulesets --input <file>`. Then `scripts/p0/readback.sh <ruleset id> <scratch repo id> .github/workflows/p0-required.yml <sha>` must print `READBACK OK` (it also checks enforcement `active`, no bypass actors and the `p0-base` target). |
| S4 | owner | Give the writer account Write on this repo (V6 c1 approval, V6 f). |

Alternative to the owner status in S1: the owner runs `gh workflow enable t4-jobcheck.yml -R OperationCode/claude-review-test` (the repo variable `OC_GATE` is unset, so its `oc-claude-review-scn` job passes), closes and reopens the PR, merges, and disables it again. The status step is preferred: it is one explicit owner act per merge and leaves no producer running.

Rules while the test ruleset is on:

- The required run does not start on PRs that were open before the rule existed. Use new PRs (`p0-v6-*` names) with base `p0-base`.
- First check after S3: on the first V6 PR, a `p0-required` run must start (`event: pull_request_target`). If none starts on a `p0-base` PR, stop and use the fallback in "Default branch check" below.
- Run `scripts/p0/observe.sh <pr> 3` in its own terminal for each PR under test. It writes `p0-observe-<pr>.jsonl`. Read the box only from it: Mergeable (`CLEAN`, `UNSTABLE`, `HAS_HOOKS`), Blocked (`BLOCKED`), Other (re-read).
- A reading counts only when other blockers are ruled out on the same line: `base` is `p0-base`, `draft` false, `mergeable` `MERGEABLE` (no conflict), `review` not `CHANGES_REQUESTED`, and `other_checks` has no required check that is pending or failing. Otherwise mark the reading invalid and repeat.
- Start runs with: close and reopen (`gh pr close N && gh pr reopen N`), a push, or "Re-run all jobs" (`gh run rerun <id>`). `labeled`, `edited` and `ready_for_review` do not start a required run.

## V6: which run counts (build, first)

Prerequisites. Owner: S2, S3, S4; OK for fork pushes; the repo variable `P0_COLLECT_RUNS_ON` for the queued cells. Worker: S1, S1b; same-repo branches and PRs; comments; `gh run cancel` and `gh run rerun` (run controls: clear them with the owner).

PRs (all with base `p0-base`): S = same-repo PR from `p0-v6-same` (one commit H that adds `test-fixtures/p0/v6/marker.txt`); F = fork PR from `irvingpop:p0-v6-fork` (commit Hf). Run every case on S and on F, except c2 (S only: a `GITHUB_TOKEN` of this repo cannot write a fork). On F read H as Hf, `p0-v6-same` as `p0-v6-fork`, `origin` as the fork remote, and `p0-v6-same2` as `irvingpop:p0-v6-fork2`.

General criteria (spec): with no earlier pass on the head, the box blocks unless the newest run completed with `success`; with an earlier pass, the box blocks from the moment a newer run exists, in every state but `success`.

"Make H pass" below means: post `/p0 override <H>` (after the last push epoch), knobs `collect_sleep=0 force=none pause=0`, close and reopen, wait for `success`, box Mergeable.

"Gate failed for the missing override" means: in that run `collect` and `analyze` are `success`, and the gate summary has `result: fail` with the single reason `simulated high finding, no valid override (waivable)`.

### Cases with an earlier pass (a to g)

| Case | Steps | Record | Pass when |
|------|-------|--------|-----------|
| a1 absent replacement | Make H pass. Delete the override comment (revoke). Wait 3 min, start no run. | box | Record only: the box stays Mergeable (stated residual). |
| a2 in progress, failed | Knobs `collect_sleep=60`. Close and reopen. | reopen time (timeline `reopened` event, `scripts/p0/v16-check.sh`) and the new run's `created_at` (gap); box while in progress; box after `failure`; gate summary | Blocked from the new run's creation through its failure, and the gate failed for the missing override. A failure of `collect` or `analyze` (timeout, API error) does not count: repeat. |
| a3 cancelled | Make H pass. Delete override. Knobs `collect_sleep=120`. Reopen. `gh run cancel <id>` within the first 100 s of `collect`. | box per state; run conclusion | Blocked while pending and after `cancelled`. If the run ends `failure` or `success` because the cancel was late: repeat. |
| a4 timed out | Make H pass. Delete override. Knobs `force=timeout`. Reopen. | box; run and job conclusions (`collect` timed out) | Blocked while pending and after the timeout. |
| a5 clears | Post a new override for H. Knobs `collect_sleep=60`. Reopen. | box while pending, then after `success` | Blocked while pending, Mergeable after `success`. |
| b1 A finishes last | Make H pass setup (override valid). Knobs `pause=300`. Reopen: run A. Wait for A's log line `pausing ... (result already fixed: pass)`. Delete the override, knobs `pause=0`, close and reopen: run B fails. Wait for A to exit 0 and complete. | `completed_at` of A and B; box after each completes | Blocked after A completes (A finished last with `success`). |
| b2 B passes, A superseded | Override valid. Knobs `collect_sleep=120`. Reopen: run A. Knobs `collect_sleep=0`. Reopen: run B passes. A reaches its final check after B exists and exits `superseded`. | `completed_at` of both; A's `newer_runs`; box after each completes | Mergeable after A completes (the box follows B, the newest run). Blocked after A completes, with other blockers ruled out, means the last completed run decides: stop rule. |
| c1 H->B->H, user push | Make H pass. Writer approves the PR. Force-push the head to B (`git push -f origin B:p0-v6-same`), wait for B's run. Knobs `collect_sleep=120`. Force-push back to H. | `review` before and after the push of B; box while the new run on H is pending and after it fails (the old override is older than the epoch) | Blocked while pending and after `failure`; approval dismissed by the push of B. |
| c2 H->B->H, GITHUB_TOKEN push (S only) | Make H pass again (new override). Push B (user). Dispatch `p0-v6-token-push` (from `main`, after S1) with `branch=p0-v6-same`, `sha=H`. | whether a run starts on H; box | Record only: no run starts and the box shows the old pass (stated residual). |
| e1 re-run newest | Newest run failed (no override). Post override. `gh run rerun <newest id>`. | attempt 2 result; box | The box follows attempt 2 (Mergeable on `success`). |
| e2 re-run older | Override valid: run A passes. Knobs `force=fail`, reopen: run B fails. Knobs `force=none`. `gh run rerun <A>`. | A attempt 2 (expect `superseded`); box | Blocked throughout. |
| f run deletion (writer) | Make H pass (run A). Newer run B with `force=fail`. As the writer: `gh run delete <B>`. Repeat with B cancelled (a3 setup), B timed out (a4 setup), and B pending (try the delete while it runs). | box and `mergeable` after each delete; the run list for H | Blocked after each delete. If Mergeable: writers can restore an older pass; the owner accepts this or the design changes. |
| g1 branch delete and restore | With H passed: delete the head branch (S: `git push origin --delete p0-v6-same`; F: the fork owner runs `git push <fork> --delete p0-v6-fork`). The PR closes. Click "Restore branch" on the PR page (F: as the fork owner). Reopen the PR. | timeline events; whether restore or reopen starts a run; box | Record which run decides. |
| g2 second PR, same head | Push `p0-v6-same2` at H (F: `p0-v6-fork2` at Hf in the fork) and open PR 2 to `p0-base`. No comments on PR 2 (its run fails). | box on PR 1 and PR 2; run list for H | Record which run decides each PR. |

### Cases with no earlier pass (fresh heads)

Each case uses a new commit that no run has passed. Commit it locally first, so its SHA is known before the push. Post knobs (and the override, when the case needs one) before the push; a normal push is not a push-epoch event.

| Case | Steps | Record | Pass when |
|------|-------|--------|-----------|
| n1 queued, then cancelled | Owner: `gh variable set P0_COLLECT_RUNS_ON -R OperationCode/claude-review-test -b p0-hold-queue`. Push new commit N1. Wait until observe shows the newest run `queued` for at least 2 polls. Owner: `gh variable delete P0_COLLECT_RUNS_ON -R OperationCode/claude-review-test`. `gh run cancel <id>`. | box while `queued`; box after `cancelled` | Blocked in both states. |
| n2 in progress, failed | Knobs `collect_sleep=60 force=none`, no override. Push N2. | box while in progress; after `failure`; gate summary | Blocked in both states; the gate failed for the missing override. |
| n3 timed out | Knobs `force=timeout`. Push N3. | box; `collect` timed out | Blocked while pending and after the timeout. |
| n4 success | Override for N4, knobs `collect_sleep=60 force=none`. Push N4. | box while pending, then after `success` | Blocked while pending, Mergeable after `success`. |
| d cancel in collect | Knobs `collect_sleep=120 force=none`. Push N5. `gh run cancel <id>` within the first 100 s of `collect`. | run conclusion; box | Run ends `cancelled`; Blocked. If the cancel was late and the run completed: repeat. |

Queued with an earlier pass (cell "queued" in the matrix below): make H pass, delete the override, set the variable, close and reopen, then the same steps as n1.

If the run fails at once instead of staying `queued` (no runner with that label), or `queued` never shows in 2 polls, leave the queued cell incomplete. Repeat under a controlled queue (for example, a self-hosted runner that the owner registers and stops) before V6 closes.

### Results matrix

Fill one cell per state, per PR type, per column. Each cell: box seen, run id and attempt, the `p0-observe-<pr>.jsonl` line times, and "valid" (other blockers ruled out). An empty cell means V6 is not complete.

| Newest run state | S, no earlier pass | S, earlier pass | F, no earlier pass | F, earlier pass | Expected |
|------------------|--------------------|-----------------|--------------------|-----------------|----------|
| absent (no newer run) | n/a | a1 | n/a | a1 | earlier pass: Mergeable (residual) |
| queued | n1 | queued + earlier pass | n1 | queued + earlier pass | Blocked |
| in progress | n2 | a2 | n2 | a2 | Blocked |
| failure | n2 | a2, c1 | n2 | a2, c1 | Blocked |
| cancelled | n1, d | a3 | n1, d | a3 | Blocked |
| timed out | n3 | a4 | n3 | a4 | Blocked |
| success | n4 | a5 | n4 | a5 | Mergeable after `success` |

### Stop rule

Stop the build, and change the gate design, if any of these shows that an older run or the last completed run decides:

- an "earlier pass" cell in the matrix is Mergeable while the newest run is not `success` (the absent row is the stated residual, not a stop);
- b1: Mergeable after A completes;
- b2: Blocked after A completes `superseded` while B, the newest run, is `success`;
- c1 or e: Mergeable while the newest run or attempt is not `success`.

Before applying the rule, the reading must be valid (other blockers ruled out, see "Rules while the test ruleset is on"). b2 liveness is part of the rule: a verified Blocked in b2 stops the build. f and g are record-only for the stop rule; their results go to the owner as residuals.

### Default branch check

The production ruleset targets `~DEFAULT_BRANCH`; this plan uses `p0-base` so `require-scn` stays on. After the matrix, confirm that the box behaves the same on `main`: the owner adds `~DEFAULT_BRANCH` to the test ruleset include list (read back with `P0_REF_INCLUDE='~DEFAULT_BRANCH,refs/heads/p0-base'`), the worker opens a fresh same-repo PR to `main`, and the owner posts the `oc-claude-review-scn` status (S1 command) on its head. Run n2 and n4 on it. Pass: the same box readings as on `p0-base`, with `other_checks` showing `oc-claude-review-scn` `success` on every line. Then remove `~DEFAULT_BRANCH` again. If the first V6 PR on `p0-base` got no required run, use this setup for all of V6 instead, and post the status on every new head before reading the box.

## V2: OIDC in a ruleset-required run (build)

Prerequisites: as V6 (S1b, S2, S3, fork push OK). It runs on the first V6 runs (PRs to `p0-base`): no extra steps.

1. On PR F (fork) and PR S, open the `analyze` job summary of the first `p0-required` run.
2. Record the decoded claims and the `checks` block. Compare `job_workflow_sha` with the ruleset `sha` (S3 read-back).

Pass: `job_workflow_ref` names the scratch repo's `p0-required.yml`, `repository_owner_id` is `10479364`, `event_name` is `pull_request_target`, and `job.workflow_sha` equals `job_workflow_sha` equals the pinned SHA. If the mint fails or a value is wrong: stop, the auth design changes.

## V3: federation rule with list and prefix conditions (build)

Prerequisites. Owner: Anthropic test workspace, service account, GitHub issuer and a TEST federation rule (below); V2 setup. Worker: commit the four IDs into the scratch file and `p0-v3-other-repo.yml` (scratch commit needs the owner: it moves the pin).

Doc check (done, see the phase 0 report): the WIF reference puts `issuer_url` on the issuer (`https://token.actions.githubusercontent.com`, JWKS `discovery`), and `audience`, `claims` (exact strings) and `condition` (CEL, variable `claims`, `startsWith` and `in` shown in the reference example) on the rule `match`. Test rule:

```
issuer:   issuer_url https://token.actions.githubusercontent.com, jwks: discovery
rule:     oauth_scope workspace:inference, token_lifetime_seconds 600, workspace_id <test workspace>
match:
  audience:  https://api.anthropic.com
  claims:    { repository_owner_id: "10479364", event_name: "pull_request_target" }
  condition: claims.job_workflow_ref.startsWith("OperationCode/<scratch repo>/.github/workflows/p0-required.yml@")
             && claims.job_workflow_sha in ["<pinned SHA>"]
```

1. Put the IDs in `p0-required.yml` (`P0_FEDERATION_RULE_ID`, `P0_ORGANIZATION_ID`, `P0_SERVICE_ACCOUNT_ID`, `P0_WORKSPACE_ID`), push to scratch `main`, add the new SHA to the rule list, move the ruleset pin to it, read back.
2. Accept: open or sync a V6 PR. `analyze` shows `v3_exchange_http: 200`.
3. Another repo: put the same IDs in `p0-v3-other-repo.yml` (PR to `main`, merge with the owner status from S1), open a same-repo PR from a `p0-v3` branch. Expect `exchange_http: 401`.
4. Another event: in the scratch repo, Actions, `p0-required`, "Run workflow" (`workflow_dispatch`). Expect `v3_exchange_http: 401`.
5. Unapproved SHA: push a no-op commit to scratch `main` (S2'), move the ruleset pin to S2' (not in the rule list), read back, sync a PR. Expect 401. Then add S2' to the list or move the pin back.
6. Record the deny reason of each 401 from the Console authentication history.

Pass: 2 is 200; 3, 4 and 5 are 401. Record the final rule text in the spec. If the rule cannot be expressed or a bad token passes: stop, the auth design changes.

## V4: Dependabot PRs (build)

Prerequisites. Owner: S2, S3; dependency graph on (for "Check for updates"); the S1 status on the staging PR. Worker: the staging PR below.

1. After S3: copy `test-fixtures/p0/v4/dependabot.yml` to `.github/dependabot.yml` in a PR to `main`, and merge it with the owner status from S1. Dependabot reads the file on `main` and opens one PR to `p0-base` (`target-branch`) that bumps `is-number` in `test-fixtures/p0/v4`. If none appears, the owner uses Insights, Dependency graph, Dependabot, "Check for updates", or comments `@dependabot recreate`.
2. Run `scripts/p0/observe.sh <dependabot pr>`. Read the `analyze` summary of its `p0-required` run (`mint`, `actor`, claims) and the gate summary.
3. Optional: post an override, close and reopen; record that the box clears.

Pass: `analyze` mints a token (`mint: ok`), and the box shows the required run's result (Blocked on the gate's `fail`, Mergeable after an override pass).

## V5: one request with three features (build)

Prerequisites. Owner: a test or eval workspace credential. No GitHub prerequisite.

`ANTHROPIC_API_KEY=<test key> scripts/p0/v5-request.sh` (or `ANTHROPIC_AUTH_TOKEN=<WIF access token>`). One request: mid-conversation `system` message as the last entry after the user turn, `output_config.format` with the spec's findings schema, `fallbacks: "default"` with beta `server-side-fallback-2026-07-01`. Record HTTP status, `stop_reason`, `model`, `usage`, `content_types`, `parsed`.

Pass: HTTP 200, `stop_reason` `end_turn`, the text parses as findings JSON. Fail (400 naming a feature): the spec fallback applies (pass instructions in the top-level `system`, 3 cache entries); record it.

## V9: spend limit behavior (build)

Prerequisites. Owner: a test workspace with a very small hard spend limit and a credential for it.

1. `ANTHROPIC_API_KEY=<tiny-limit key> scripts/p0/v9-spend.sh`. It stops at the first non-200 and logs every call to `v9-log.jsonl`.
2. In the Console, read the workspace spend. Overshoot = spend minus limit. Record the HTTP status, error type and message of the first failed call.
3. Fail closed: bind the V3 test rule to this workspace, set `P0_MESSAGES_CALL: "true"` in the scratch file (new SHA, pin move, read back), sync a PR. `analyze` must fail with the Messages error, and the box must block.

Pass: the limit error is recorded with the overshoot, and the run fails and blocks.

## V13: dependency review on fork PRs (build)

Prerequisites. Owner: dependency graph on for this repo (today the compare API returns 403 here); OK for fork pushes. Worker: S1 (`pull_request_target` uses the file on `main`).

1. Vulnerable PR: in the fork, branch `p0-v13-vuln` from `main`: copy `test-fixtures/p0/v13/package.json.fixture` to `p0-v13/package.json` and `package-lock.json.fixture` to `p0-v13/package-lock.json`. Push, open a PR to `main`.
2. Control PR: in the fork, branch `p0-v13-safe` from `main`: copy `test-fixtures/p0/v13/safe/package.json.fixture` and `safe/package-lock.json.fixture` to `p0-v13/` the same way (lodash 4.18.1, minimist 1.2.8). Push, open a PR to `main`. Same token, event and SHA-ref setup.
3. Read each `p0-v13-dependency-review` run: `snapshot` (head and merge base SHAs, `compare_http`, high or critical added changes from the compare API), `dependency-review`, and `report` (`result`).

The `report` job classifies each run and fails unless `result` is `PASS`:

| Run | PASS | FAIL | INCOMPLETE |
|-----|------|------|------------|
| vuln | compare API 200; exported step `outcome` `failure`; the action's `vulnerable-changes` lists lodash or minimist at high or critical | compare API 200 shows a high change, but `outcome` is `success` | compare API not 200, snapshot failed, or a failure with no expected vulnerable change (setup or API error) |
| safe | compare API 200; `outcome` `success`; no high or critical change | `outcome` `failure` with a high or critical change listed | anything else |

Pass: vuln PASS and safe PASS. INCOMPLETE is an infrastructure result, not a V13 result: fix the cause and re-run (`gh run rerun`). A red job alone is not evidence.

## V16: push epoch events (build)

Prerequisites. Owner: OK for fork pushes. Worker: push branch `p0-v16-base` to this repo, PR actions, run the script locally. No workflow and no ruleset needed.

Fork branch `p0-v16` in `irvingpop/claude-review-test`. After each step run `scripts/p0/v16-check.sh <pr>` and keep the output.

1. Push commit A, open the fork PR. Post `/p0 override <A>`.
2. Force-push B (a different commit, not a descendant of A).
3. Force-push A again. The override for A must now show `rejected because before-epoch`.
4. Delete the fork branch (`git push <fork> --delete p0-v16`), then "Restore branch" on the PR page, then reopen if it closed.
5. Retarget: `gh pr edit <pr> --base p0-v16-base`, then back to `--base main`.
6. Close the PR. Force-push the fork branch to an earlier SHA (for example the parent of A). Reopen (GitHub may refuse; record).

Pass: the timeline shows `head_ref_force_pushed`, `head_ref_deleted`, `head_ref_restored` and `base_ref_changed` with server times, and the override for A is rejected. Record what step 6 shows; if nothing, add `reopened` to the epoch events in the spec.

## V18: fork head objects through the base repo (build)

Prerequisites. Worker: a push of `phase0-tests` and a PR (part 1); S1 (part 2). Owner: OK for fork pushes (part 3 only).

1. Now: open the same-repo PR `phase0-tests` -> `main`. The PR's own `p0-v18-fork-objects` runs on `pull_request` and reads every open fork PR (#4 from kylemh, #10 from irvingpop) through `repos/OperationCode/claude-review-test/git/...` with the run's `GITHUB_TOKEN`. No merge needed.
2. After S1: dispatch `p0-v18-fork-objects` with `pr_number` 4 and 10 (`workflow_dispatch` needs the file on `main`).
3. Spec case, after S1: a fork PR from a `p0-v18` branch runs it on `pull_request_target`.

Each row records `tree_valid`, `tree_truncated`, `blobs_total` (unique blobs in the recursive tree), `blobs_checked`, `blobs_ok` and `blobs_failed`. The step prints `result` and exits nonzero unless it is `PASS`.

Pass: `result: PASS`: at least one target, and in every row the commit read is 200, the tree is valid and `truncated` is `false`, `blobs_checked == blobs_total`, and every blob is 200. `INCOMPLETE` (no target, cap hit, bad or truncated tree) is not a pass: raise `max_blobs` or fix the cause and re-run. `FAIL`: a read was refused.

## V24: run list for the final check (build)

Prerequisites. Worker: as V18 parts 1 and 2. Owner: S2, S3 for ruleset-started runs; fork push OK for a fork PR.

1. Now: the PR `phase0-tests` -> `main` also runs `p0-v24-run-list` on `pull_request` (6 min). While it polls, close and reopen the PR twice. For each new run read `delay_min_s` and `delay_max_s` (epoch seconds; the run was absent from the response to the request sent at `prev_req`, and present in the response received at `resp`). Runs with `predates_poll: true` existed before the first poll and give no delay.
2. After S1: fork PR from a `p0-v24` branch (pull_request_target), same steps; or dispatch with the head SHA of PR #10.
3. Ruleset-started runs: during V6 b1, the paused gate job logs run B with `delay_min_s` and `delay_max_s`. Or dispatch `p0-v24-run-list` with a V6 head SHA and reopen that PR.

Pass: the token lists runs by head SHA on fork and same-repo PRs, including ruleset-started runs, with `path`. Record the delay bounds. A delay does not stop the build.
