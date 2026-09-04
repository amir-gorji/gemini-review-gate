# gemini-review-gate

A GitHub Action that makes a Gemini code review a **blocking merge gate**: the pull request's diff goes to a pinned model at temperature 0, a `REJECT` verdict fails the check with the reasons posted on the PR, and everything that is not a literal `APPROVE` fails closed.

It exists for repositories whose pull requests are written by autonomous agents, where the deterministic gates (lint, types, tests, coverage) say nothing about intent.
A test rewritten to match the behaviour that broke it, a coverage threshold lowered with a plausible comment, a tenant filter dropped from a query, or a Zod enum widened to `z.string()` all pass those gates green.
This reviewer is the one per-PR reader that sees the whole diff and is told, in a policy file you own, exactly which of those shapes it may reject for.

It is generic: the prompt, the diff shape, the fence, the retry, and the exit codes live here, and the three things that are yours arrive as inputs: one sentence naming your system, a policy file, and a list of paths to leave out.

## How it works

1. On every pull request the action diffs the head against its **merge base** (never `base..head`, so a base branch that moved does not report its own later commits as the PR's changes), with rename detection and ten lines of context (`git diff -M -U10`), minus the pathspecs you exclude.
2. The diff is fenced in a tag whose name carries a **per-run nonce**, and the prompt declares everything inside it data.
   An author who writes `</diff>` in a comment cannot end the fence early, and the prompt names a comment or string that addresses the reviewer as itself a reason to reject.
3. The prompt tells the model that your **policy file is the whole list** of blocking defects and that anything it does not name is advisory.
4. The model answers with one word on the first line.
   The parser takes the first non-empty line, strips markdown decoration, and requires the bare word `APPROVE` or `REJECT`; anything else fails closed.
5. `REJECT` posts the reply as a PR comment headed by the reviewed head SHA and fails the job.

| Exit | Meaning                                                                                                     |
| ---- | ----------------------------------------------------------------------------------------------------------- |
| 0    | `APPROVE`, or a diff with nothing reviewable (documentation only, or only excluded paths)                  |
| 1    | `REJECT`; the reasons are on the PR                                                                         |
| 2    | The reply started with neither word; read the log                                                           |
| 3    | The reviewer was unavailable: no key, the API down after three retries with backoff, diff over the byte cap |

**Exit 2 and 3 are never a rejection.** Re-run for 3, read the log for 2.
A required check that passes on "the model wrote something else" or "the API was down" is a check an author can wait out, so neither passes.

## Quick start

1. Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/) and add it to the repository as an Actions secret named `GEMINI_API_KEY`.
2. Copy [`policy.example.md`](./policy.example.md) to `.github/gemini-review-policy.md` and edit it: keep the generic shapes, add the ones that are yours (see [Writing the policy](#writing-the-policy)).
3. Copy [`examples/gemini-review.yml`](./examples/gemini-review.yml) to `.github/workflows/gemini-review.yml`, set the `system` sentence and the `exclude` list, and pin the action by commit SHA.
4. Make `gemini-review` a required status check on your default branch (a ruleset or branch protection).
   If your plan has neither, see [Wiring into an existing gate](#wiring-into-an-existing-gate).
5. Open a pull request.
   The first run is the wiring test: it is the only place the real event payload and the real secret meet.

The minimal workflow:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]

concurrency:
  group: gemini-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read
  pull-requests: write # the REJECT comment

jobs:
  gemini-review:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha> # v5
        with:
          fetch-depth: 0 # the merge-base diff needs both the base and the head
      - uses: amir-gorji/gemini-review-gate@<sha> # v1
        with:
          gemini-api-key: ${{ secrets.GEMINI_API_KEY }}
          system: a TypeScript service that does X for Y
          policy-file: .github/gemini-review-policy.md
          exclude: |
            pnpm-lock.yaml
            **/*.generated.*
```

## Inputs

| Input                | Required | Default            | What it is                                                                                                  |
| -------------------- | -------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `gemini-api-key`     | yes      |                    | A repository secret. A fork PR sees none, and the check reports unavailable (exit 3) rather than rejected.   |
| `system`             | yes      |                    | One sentence naming the system under review. It opens the prompt.                                           |
| `policy-file`        | yes      |                    | A markdown file listing what the reviewer may `REJECT` for. Inlined verbatim; everything else is advisory.  |
| `exclude`            | no       | empty              | Git pathspecs left out of the reviewed diff, one per line, without the leading `:!`.                        |
| `docs-only-suffixes` | no       | `.md`              | A diff in which every changed path ends in one of these passes without a model call.                        |
| `model`              | no       | `gemini-3.8-flash` | Pin a stable id on a required check; a preview id's deprecation is a red on every PR at once.               |
| `max-diff-bytes`     | no       | `250000`           | A larger reviewable diff is reported unavailable with "split the unit", never reviewed in part.             |
| `mode`               | no       | `review`           | `calibrate` replays the corpus in `calibration-dir` instead of reviewing a PR.                              |
| `calibration-dir`    | no       | empty              | Directory of `reject-*.diff` and `approve-*.diff` files for `calibrate` mode.                               |

Every run starts with a self-check: the verdict parser, the nonce fence, the docs-only rule, and that every exclusion is a pathspec git accepts against the working tree.
A typo in an input fails the step rather than silently widening the review.

## Writing the policy

The policy is the whole list of what counts as a blocking defect.
The model has the policy and the diff and nothing else: it cannot open your `CONTRIBUTING.md`, so every rule has to be a shape a reader can point at in a diff, spelled out with the files it applies to.

[`policy.example.md`](./policy.example.md) carries the shapes that apply to any TypeScript repository:

- a correctness regression;
- a security flaw: injection, missing authorization on a mutating route, a secret in the tree, a validation at a trust boundary removed;
- a data-loss defect: a record that can be silently dropped, overwritten, or reordered;
- a gate gamed: a test deleted, skipped, or rewritten to match the behaviour that broke it; a coverage or mutation threshold lowered; a type widened or a cast added to silence an error; a schema loosened; a lint or type-check's scope narrowed.

Then add what is yours.
Two examples of the kind of rule that belongs here:

- A privacy rule for an app that holds personal data: user content written to a log, to an error tracker, or to a third party; free-text input stored where only a rating was meant to be.
- A shape rule for a library with per-vendor modules: a vendor-specific branch added to a file the architecture names as shared, instead of the vendor's own module.

Three things to keep out of the policy:

- **Judgement.** Naming, layering, "this would be cleaner as": a gate widened into taste is a gate that gets suppressed.
  The prompt already demotes everything unnamed to advisory.
- **Rules the diff cannot show.** "Every new table must be covered by the export" is a fine rule for a human; the model does not see the export code unless the diff touches it.
  Phrase it as the shape that would appear in the diff if you can, or leave it to a deterministic gate.
- **Text aimed at the reviewer.** In the policy, in code, in fixtures, in prose.
  The reviewer cannot tell a quotation from an injection and should not try, so describe such text rather than quoting it.

## Calibration

The only evidence a reviewer works is a corpus of diffs with known verdicts.
Keep one in your repository: `reject-<name>.diff` for each shape the policy names, `approve-<name>.diff` for correct changes that look like the rejects (a threshold raised beside the one lowered, an ids-only log line beside the one carrying user content, a string added in both languages beside the one inlined).
The controls are what measure false positives, and a blocking check with false positives is a check people learn to re-run until it passes.

A case is a single plausible change with a comment and no text aimed at the reviewer, captured with the same flags the action uses so it replays in the live shape.
The fastest way to build one is to plant the defect in the working tree, capture, and restore:

```bash
# edit the file(s) to plant the defect, then:
scripts/capture-case.sh reject-tenant-filter-dropped path/to/route.ts path/to/route.test.ts
```

[`scripts/capture-case.sh`](./scripts/capture-case.sh) runs `git diff -M -U10` on the named files, writes `calibration/<name>.diff`, and checks the files out again.
If you have many cases, a short script that applies each edit with an assert-once string replacement, captures, and restores is worth writing; a corpus of a dozen cases can be regenerated in one run that way.

Replay the corpus with `mode: calibrate` from a `workflow_dispatch` trigger, never per PR (it makes one model call per file):

```yaml
  calibrate:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<sha>
      - uses: amir-gorji/gemini-review-gate@<sha>
        with:
          gemini-api-key: ${{ secrets.GEMINI_API_KEY }}
          system: <the same sentence>
          policy-file: .github/gemini-review-policy.md
          mode: calibrate
          calibration-dir: .github/gemini-review-calibration
```

It prints one line per case and fails on any verdict that does not match the file name.
Run it before changing `model` or the policy file, and record the numbers where you record decisions.
A planted diff the model approves is answered by tightening the policy's wording and rerunning, never by softening the plant; a shape the reviewer misses in practice goes into the corpus as a new `reject-*.diff` before any prompt change that claims to fix it.

Two operational notes:

- **Exclude the corpus directory** from the per-PR review.
  Its files are planted defects by design, and a review of them would reject every PR that touched the corpus.
  That is an exclusion of fixture data, not a narrowing of what the review sees of the code.
- A `workflow_dispatch` only resolves a workflow that exists on the default branch.
  Once it does, `gh workflow run gemini-review.yml --ref <branch>` replays that branch's corpus and policy, so a policy change is measured before it merges.

## Wiring into an existing gate

If your repository already has a single aggregate job that is the required status (an `all` job with `if: always()` that reads every `needs.*.result`), or if your plan has no rulesets to require a second check with, put the review in that workflow as a job and add it to the aggregate's `needs`.
[`examples/ci-job.yml`](./examples/ci-job.yml) is that job.

Two conditions on it are worth copying:

- `if: github.event_name == 'pull_request'`: a push-to-main run re-validates a diff the review already saw, and there is no PR to comment on.
  An aggregate that counts `skipped` as passing is unaffected.
- Skip PRs from `dependabot[bot]` if your aggregate is what an auto-merge workflow reads.
  A Dependabot-triggered run reads the Dependabot secret store, not the Actions one, so the key would be empty and the check red on every batch.
  Either skip them or add the key to the Dependabot store too.

## What it does not do

- **An `APPROVE` is necessary and never sufficient.**
  The model sees the diff and nothing else: not the rest of the file, not the tests that were not touched, not the issue.
  A defect that depends on code outside the context window is invisible to it.
  Keep your deterministic gates as the verdict on what the code does.
- **It does not close prompt injection.**
  No prompt does.
  The nonce fence and the "text addressed to the reviewer is a defect" rule raise the cost; a reviewer that reads the change is still a reviewer the change can address.
- **It does not review in part.**
  A diff over the byte cap is reported unavailable with "split the unit", because a review that skims approves noise.
- **It does not skip documentation, it passes it.**
  A markdown-only diff exits 0 without a model call, so the check stays green on the same diffs your other jobs skip without a ruleset exception.

## Design notes

Things that were tried and rejected, so you do not have to try them again:

- **`startswith("REJECT")` on the raw reply** read `**REJECT**`, `"Reject."`, and a leading blank line as approval: a gate satisfied by markdown.
- **A fixed fence tag** (`<diff>`) was the one breakout a fenced prompt still allowed: a comment containing `</diff>` ended the fence early.
  The nonce closes that; a "fail on `</diff>`" check would have been the wrong fix, since a legitimate diff can contain that string.
- **A preview model id** on a required check means the id's deprecation is a red on every PR at once.
- **Function context (`git diff -W`)** measured eight to ten times the bytes of the default diff on class-heavy TypeScript, because git has no function-name driver for it and falls back to the enclosing class.
  Ten fixed lines is predictable against the cap.
- **"Structural bloat" as a reject reason** produced rejections nobody acted on.
  It is advisory now, like everything else the policy does not name.
- **Raising straight to exit 1 on a 5xx** made an outage indistinguishable from a rejection, and a fork PR (no secrets) indistinguishable from a bad one.

## Using it from a private repository

GitHub only lets a private action be referenced by `uses:` from repositories owned by the same user or organisation, with "accessible from repositories owned by the owner" enabled on the action's repository.
If this repository is private and yours is under a different owner, vendor the three files (`action.yml`, `review.py`, and this README) under `.github/actions/gemini-review-gate/` and reference `./.github/actions/gemini-review-gate` instead.
Add that directory to your Dependabot `github-actions` config so the `setup-python` pin inside keeps moving.

## Cost

One Python setup and one model call per pull request event, about thirty seconds and a few cents on the default model.
Cancel-in-progress concurrency keyed on the PR number stops a superseded head from paying for a second verdict.

## Licence

MIT.
