# Test plan

Two questions from the design spec:

- **V14(e):** can one workflow run complete or re-complete, by check run ID, an `oc-claude-review` check that a different run created? And what does GitHub use when several checks have one name?
- **V17:** in a `pull_request_target` run, can the code always get the PR number, also for fork PRs?

Roles: the **owner** (admin of `OperationCode/claude-review-test`) and a **second account** (any GitHub user who is not a collaborator).

## 0. One-time setup

Owner:

1. Push the repo to `OperationCode/claude-review-test` on `main`. The `pull_request_target` workflows must exist on `main` before any PR is opened.
2. Settings, Actions, General, "Workflow permissions": keep the default (read repository contents). The workflows set their own permissions per job.
3. Settings, Actions, General, "Fork pull request workflows from outside collaborators": choose "Require approval for first-time contributors" (or stricter). Runs of `pull_request_target` come from the base branch, so they may start with no approval. See step 3.1.
4. Create `branch-a` with one small change to `README.md` (any text). Do not merge it.

For the merge box tests (part 4) only:

5. Settings, Rules, Rulesets, New branch ruleset: target `main`, enforcement Active, rule "Require status checks to pass", add the check `oc-claude-review-scn` (source: GitHub Actions; if the picker does not list it yet, type the name after the first scenario run). Do not add a ruleset that requires `oc-claude-review`: it would make part 4 read `BLOCKED` for the wrong reason. Create this ruleset only when you start part 4, and disable it after.

## 1. V14(e) and V17, same-repo PR (owner)

Open the PR first, then run the steps in order. After each step, wait until all workflow runs of that step show a finished state (green or red), do not go by time, then read the summaries listed. The merge state is read a few seconds after the writes and can lag.

Checks belong to one head SHA, so steps 1.1 to 1.4 use head H1 and steps 1.5 and 1.6 use head H2.

| Step | Action | Expected check state afterwards (name `oc-claude-review`) |
|------|--------|-----------------------------------------------------------|
| 1.1 | Open a PR `branch-a` to `main`. | H1: c1 `in_progress`. |
| 1.2 | Close the PR, then reopen it. | c1 `cancelled` (by run 2), c2 `success`. |
| 1.3 | Close and reopen again. | c2 `cancelled` (by run 3), c3 `success`. |
| 1.4 | Open the `v14e-cross-run-check` run of step 1.3 and click "Re-run all jobs". Do the same for the `v17-pr-number` run of step 1.3. | c3 `cancelled` (by attempt 2), c4 `success`. |
| 1.5 | Push one new commit to `branch-a`. | H2: c5 `in_progress`. H1 is untouched. |
| 1.6 | Open the `v14e-cross-run-check` run of step 1.5 and click "Re-run all jobs". Do the same for the `v17-pr-number` run of step 1.5. | c5 `cancelled` (by attempt 2), c6 `in_progress`. |
| 1.7 | Optional: push two commits within 5 seconds. | Two concurrent runs. V14(e2) race evidence. |

Read, for every step:

- Actions, run `v14e-cross-run-check`, job `cross-run`, job summary. Fields: `verdict`, `evidence`.
- Actions, run `v17-pr-number`, job `with-actions-read`, job summary.

The four cells of the cross-run matrix:

| Creator of the older check | Older check `in_progress` | Older check completed |
|----------------------------|---------------------------|-----------------------|
| Different run | step 1.2 (`other-run`) | step 1.3 (`other-run`) |
| Earlier attempt of the same run (re-run) | step 1.6 (`rerun-same-run-id`) | step 1.4 (`rerun-same-run-id`) |

## 2. V14 merge box notes (owner, optional on same PR)

On the PR page after steps 1.2 and 1.5, write down what the merge box and the "Checks" tab list show for `oc-claude-review`: how many entries, and which state. Compare with `final_state.pull_graphql` in the `v14e` summary. The `filter_latest` and `filter_all` lists are API facts only (see part 5).

## 3. Fork PR (second account)

Steps for the second account:

1. Open `https://github.com/OperationCode/claude-review-test` and click Fork. Create the fork in the personal account.
2. In the fork, edit `README.md` on a new branch `fork-branch-a` (change one line, commit). Optional second PR from a branch named `fork/branch-b`: it tests the head query with a slash.
3. Click "Contribute", "Open pull request", base `OperationCode/claude-review-test` `main`. Create the PR.

Owner, after the second account opens the PR:

3.1. Actions tab: write down whether the two runs of the fork PR start by themselves or show "Approve and run" or "Waiting". Runs of `pull_request_target` probably start with no prompt. If so, that is evidence for spec item V8: write it down and go on. If a prompt shows, approve it.
3.2. Read the same summaries as in part 1 (`v14e-cross-run-check`, `v17-pr-number`).

Then repeat on the fork PR. The fork PR has its own head SHAs, so the matrix cells fill the same way as in part 1. Wait for all runs to finish between steps.

| Step | Who | Action | Expected check state afterwards | Matrix cell |
|------|-----|--------|---------------------------------|-------------|
| 3.3 | Owner | Close and reopen the fork PR. | F1: c1 `in_progress` (from 3.2) becomes `cancelled`, c2 `success`. | other-run, in_progress |
| 3.4 | Owner | Close and reopen again. Wait for the runs. | c2 `cancelled`, c3 `success`. | other-run, completed |
| 3.5 | Owner | Open the `v14e-cross-run-check` run of step 3.4 and click "Re-run all jobs". Do the same for the `v17-pr-number` run. | c3 `cancelled`, c4 `success`. | rerun, completed |
| 3.6 | Second account | Push a new commit to `fork-branch-a`. | F2: c5 `in_progress`. | (setup) |
| 3.7 | Owner | Open the `v14e-cross-run-check` run of step 3.6 and click "Re-run all jobs". Do the same for the `v17-pr-number` run. | c5 `cancelled`, c6 `in_progress`. | rerun, in_progress |

Optional: the second account force-pushes the fork branch, and the owner repeats step 3.7. This checks `pull_requests[]` after a force-push.

## 4. V14 scenarios on one head SHA (owner)

Needs the ruleset from setup step 5. Do this on a **separate PR** from a new branch `scn-branch`, not on `branch-a`. Before you open it, disable the workflows `v14e-cross-run-check` and `v17-pr-number` (Actions tab, the workflow, "..." menu, "Disable workflow"). Otherwise each push adds an `oc-claude-review` check and mixes into the reads. Enable them again after part 4.

Use a fresh head SHA per scenario: push an empty commit to `scn-branch` (`git commit --allow-empty -m s`), copy the new full head SHA from the PR (Commits tab, copy full SHA).

For each scenario `a`, `b`, `c`, `f`, `g`: Actions, `v14-scenarios`, "Run workflow", enter `scenario`, `head_sha`, `pr_number`, leave `check_name` as `oc-claude-review-scn`. After the run, read the summary, and look at the PR merge box and the Checks tab. Write down which state the box shows (blocked, ready) and how many entries it lists for the check name.

Also run scenario `a` once for the **fork PR**: `pr_number` is the fork PR number and `head_sha` is the current head of the fork branch (copy it from the fork PR, Commits tab). The workflow creates the checks in the base repo with the base repo token. Disable the two other workflows first, as above.

## 5. How to read results

### V14(e), cross-run complete

In the `v14e-cross-run-check` summary, each older check has one `write` entry in `evidence`.

| Result | Meaning |
|--------|---------|
| `ok: true` and `persisted: true` for `complete_in_progress`, `relation: other-run` | PASS: a run can complete a check another run created. |
| Same for `recomplete_completed` (a completed check changes its conclusion) | PASS: a completed check can be completed again. Open-gate cancel and the publisher re-check work. |
| `relation: rerun-same-run-id` passes too | PASS: also works across attempts of one run (the re-run case). |
| `http: "HTTP 403"` or `"HTTP 404"` or `"HTTP 422"`, or `persisted: false` | FAIL. Record the `error` text. The design must change before blocking (spec V14). |
| Passes for `complete_in_progress` but fails for `recomplete_completed` | PARTIAL. The publisher re-check (set own check back to `cancelled`) does not work. Record it. |

`verdict.all_cross_run_writes_persisted: true` and a `write` entry in each of the four cells of the matrix (part 1) means full PASS. Read the check list at the same head for each cell.

### V14(d), IDs

- `verdict.ids_increasing_vs_older: true` in v14e (`null` when there was no older check, as in step 1.1), and `v14d_ids_increase_in_creation_order: true` in each scenario run: PASS. Any `false`: FAIL, and "the newest is the highest ID" cannot be used.

### V14(e2), list freshness

- `verdict.list_reads_needed: 1` (from the `visibility` entry in `evidence`) with `visible: true`: the own check shows in the list at once.
- The `older_checks` entry in `evidence`, field `count`, equal to the number of earlier checks, in a quick re-run (steps 1.2, 1.3, 1.4): the check list shows another run's check at once. If an earlier check is missing in `older_checks` (compare with the ID list in the Checks tab or in `final_state.filter_all`): FAIL for "reads at once". The publisher must wait and read again.
- The race in step 1.7 may show one run that does not see the other run's check. Record it. It is not a fail alone.

### V14(a), (b), (c), (f), (g): which check counts

For each scenario read `evidence` entries with `step: "snapshot"`, and your notes on the merge box.

| Scenario | Pass condition (spec) | Where to read |
|----------|-----------------------|---------------|
| `a` older success, newer in_progress | merge blocked | `pull_graphql.mergeStateStatus` is `BLOCKED` (or the rollup entry for the name is `IN_PROGRESS` and `isRequired` true), and the box shows the check as pending |
| `b` older failure, newer success | merge allowed | `mergeStateStatus` is `CLEAN`, box shows success |
| `c` older success completed after newer failure | record which wins | compare the two snapshots: "newer failure" vs "older success completed later". The winner rule is either by ID or by completion time |
| `f` older cancelled, newer success | merge allowed | `mergeStateStatus` is `CLEAN` |
| `g` same check re-completed `success`, `cancelled`, `success` | the last write wins | the snapshots follow the last conclusion |

Only the PR page, `mergeStateStatus` and the GraphQL rollup entry for the name answer the merge box question. The REST check lists (`check_list_filter_latest`, `check_list_filter_all`) are API facts only: the Checks API defines `filter=latest` as the most recent check runs by completion time, so it says nothing about the merge box. Record them, but do not use them as merge box evidence. For scenario `c`, the winner is the state the PR page shows after each snapshot.

A `mergeStateStatus` of `UNKNOWN` or `BEHIND` or `UNSTABLE` is not an answer: wait a minute, read the PR page by eye and note it. The summary reads the state once, 15 seconds after the writes. If the PR page disagrees with the summary, trust the PR page and write it down.

### V7, head SHA

`context.github_sha_is_not_head: true` and a successful `create` mean the workflow can create a check on the PR head SHA although `GITHUB_SHA` is the default branch commit. For a fork PR, `create.ok: true` means the base repo accepts a check on a fork-only commit. `false` is a FAIL for fork PRs and the publisher must use another way.

### V17, PR number

In the `v17-pr-number` summary, see `verdict`:

| Field | Meaning |
|-------|---------|
| `event_number` | The PR number from the event payload. Should always be the right PR. |
| `run_api_pull_requests_populated_at_once` | `true`: the run API listed the PR at the start. `false`: not available. |
| `run_api_pull_requests_populated_after_15s` | `true` while the first is `false`: the data comes late. |
| `run_api_matches_event` | `true`: run API agrees with the payload. |
| `commit_pulls_matches_event`, `head_query_matches_event` | the other two sources agree or not |
| `fork` | `true` for the fork PR runs. This is the case that counts. |

Interpretation:

- Same-repo PR, `run_api_pull_requests_populated_at_once: true`, but fork PR `false` or empty: the run API is not reliable for fork PRs (the known case). The code must use `github.event.pull_request.number` in the job that has the event, and `external_id` as `<run_id>:<run_attempt>:<pr_number>` for later reads. PASS for the fallback.
- Both same-repo and fork PR show `true` in several repeats (opened, reopened, synchronize, and the re-run of `v17-pr-number`): the run API may be used, but keep the fallback unless it holds for every step.
- `github_ref_has_pr_number: false` is expected: for `pull_request_target`, `github.ref` is the default branch. It is not a source.
- `v14e` summary, `creator_run_lookup` entries: `run_pull_requests` is what the run API says about the creating run of an older check. `pr_from_external_id` is the PR number carried in the check's `external_id`. If `run_pull_requests` is empty and `pr_from_external_id` is right, the fallback is needed and works.
- If a source returns an error (`http` not `ok`), write down the code: that source is not usable.

For the design (authenticating another run), the `creator_run_lookup` entries in the `v14e` summary are the main V17 evidence: they show what the run API says about a run that created an older check, for cross-run and re-run cases.

**Out of scope for now:** the V17 half "the run API call fails without `actions: read`". In a public repo the run API is readable with no token, so a public repo cannot show it. It needs a private repo and stays an open item for the spec.

## 6. What to send back

Copy the two JSON blocks (same-repo and fork) per step into a file, or send the run URLs and the notes from parts 2 and 4. The spec update needs: the four-cell write matrix for same-repo and fork, the ID order result, the scenario table, and the `v17` verdict table for same-repo and fork.

## Clean up

Close the test PRs. The `oc-claude-review*` checks stay on old commits and do no harm. If you set the rulesets, delete or disable them when the tests end.
