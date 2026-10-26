# claude-review-test

Test bed for the OperationCode Claude PR reviewer. It holds platform tests: small workflows that answer open questions in the design spec ("Verify before building") before the real reviewer is built.

This repo is public and holds no secrets. Do not put real code here. Other tests can be added later.

## Safety rules for every workflow here

- No checkout. No PR content is ever fetched, built or run.
- Only `run` steps with the preinstalled `gh` CLI and `jq`. No third-party actions.
- Token: `GITHUB_TOKEN` only, with the least scopes per job.
- PR-controlled text (branch names) goes through `env`, never into the script text.
- Every test writes its evidence to the job summary as JSON.

## Security notes

- The repo is public. Any GitHub user can open a fork PR and start the `pull_request_target` runs without the owner (spec item V8 tests whether approval is asked). Harm is limited to runner minutes and extra check runs here.
- A fork PR can name any commit of the fork network as its head. The `v14e` run then writes to, and cancels, checks of that name on that commit. This is a lesson for the real design: the cancel step trusts the head SHA it is given.

## Tests

| File | Spec item | Trigger |
|------|-----------|---------|
| [v14e-cross-run-check.yml](.github/workflows/v14e-cross-run-check.yml) | V14(d), (e), (e2), V7, V17 cross-run | `pull_request_target` |
| [v14-scenarios.yml](.github/workflows/v14-scenarios.yml) | V14(a), (b), (c), (d), (f) | `workflow_dispatch` |
| [v17-pr-number.yml](.github/workflows/v17-pr-number.yml) | V17 (the "needs actions: read" half needs a private repo, not covered) | `pull_request_target` |

`pull_request_target` workflows run from the default branch. Merge them to `main` before you open test PRs.

## How to run

The full step-by-step plan is in [TESTING.md](TESTING.md). Short form:

1. Push this repo to `OperationCode/claude-review-test`. Set the repo settings in [TESTING.md](TESTING.md#0-one-time-setup).
2. Open a same-repo PR, re-run it, close and reopen it, push to it. Read the job summaries of `v14e-cross-run-check` and `v17-pr-number`.
3. Ask a second GitHub account to fork the repo and open a PR. Read the same summaries.
4. For the merge box tests, require the check `oc-claude-review-scn` with a ruleset, then dispatch `v14-scenarios` once per scenario.

## Layout

```
.github/workflows/
  v14e-cross-run-check.yml   cross-run complete and re-complete of oc-claude-review
  v14-scenarios.yml          several same-name checks on one head: which one counts
  v17-pr-number.yml          PR number sources in pull_request_target runs
.github/actionlint.yaml      ignores the shellcheck quoting hint for jq filters
TESTING.md                   exact test plan and how to read the results
```
<!-- fork test -->
