---
description: Write tests for the changes made in the current session. Runs the suite in an isolated subagent, fixes failures, and reruns until green.
model: sonnet
---

Write tests covering work done earlier in this session, then drive them to green. Invoked like:

```
/test
/test focus on the URL import quota path
```

`$ARGUMENTS` is an optional focus hint. If empty, infer scope from session history (files edited, features added, bugs fixed).

## Resolve scope

1. Identify what changed this session — edited files, new functions, modified behavior. Use `git status` + `git diff` if unsure.
2. Map each change to its module. Don't assume a fixed list — enumerate the project's modules / packages / services / layers as they exist in this checkout (in a single-package repo the modules are the top-level source directories). Pick the test runner per module by reading its build manifest: discover how THIS project runs tests by reading any agent guide (CLAUDE.md, AGENTS.md, .cursor/rules, README, CONTRIBUTING) and whatever build manifests are present (for example package.json scripts, Makefile, Cargo.toml, pyproject.toml / tox.ini / noxfile, go.mod, build.gradle / pom.xml, Gemfile, composer.json, melos.yaml / pubspec.yaml). Use what the repo actually declares — never assume a toolchain.
3. State the resolved scope in one line before writing:
   `Testing: {feature/change} — {module(s)}`

If nothing testable changed (pure docs, config-only, generated code) → stop and say so. Don't fabricate tests.

If scope is ambiguous (huge diff, multiple unrelated changes) → `AskUserQuestion` once to narrow.

## Write tests

For each unit of behavior:

1. **Locate the right test file.** Mirror the source path under the project's test directory/convention. Reuse existing test files when the subject already has one; create new ones only when needed.
2. **Cover the contract, not the implementation.**
   - Pure functions: input → output, success/error branches, edge cases (empty, null, boundary), error mapping.
   - Data-access / client methods: mock the transport, assert request shape + response decoding + error paths.
   - UI components: render, assert presence + interactions, snapshot/golden only if the user asked.
   - State / stores: drive state transitions, assert emitted state.
3. **Style.** Group per subject, one test per behavior. Arrange-act-assert. No shared mutable state between tests. Prefer real objects over mocks where cheap.
4. **Stay in scope.** Don't backfill tests for code you didn't touch this session. Flag gaps you notice but don't fix them.
5. **Run codegen if needed.** If the change introduced new generated types lacking their generated files, run the project's build/codegen step before testing.

## Run tests (isolated subagent)

Delegate execution to a single `Agent` call (`subagent_type: "general-purpose"`) so test output stays out of the main context. Brief it self-contained:

```
Run the project's tests and report pass/fail.

SCOPE: {list of modules touched}
COMMAND(S) TO RUN, in order:
- {the project's lint/static-analysis command, if it has one}
- {per-module test command, discovered from each module's manifest}
  (or the whole-project test command if scope is broad)

For each command, capture:
- exit code
- failing test names + file:line
- the assertion message / stack frame for each failure
- any analyzer/lint errors (treat as failures)

Do NOT edit files. Do NOT attempt fixes. Read-only execution + report.

Report format (under 300 words):
- Overall: PASS / FAIL
- Per-command: status + failure list
- For each failure: test name, file:line, one-line cause
```

## Fix failures

When the agent reports failures:

1. Read each failing test + the code under test.
2. Decide per failure:
   - **Test wrong** (bad expectation, stale mock, missing setup) → fix the test.
   - **Code wrong** (regression revealed by the new test) → fix the code, only if the fix is within the session's scope. If the failure exposes a pre-existing bug outside scope, surface it and ask before fixing.
3. Don't loosen assertions to make tests pass. Don't skip / mark-as-skipped to hide failures. Don't catch-and-swallow.
4. Don't add retries or timing hacks for flakiness — find the real cause.

## Rerun

Re-delegate the same execution agent (fresh `Agent` call, same brief) after fixes. Repeat fix → rerun until:

- Overall PASS, or
- Three rerun cycles with the same failure → stop, report what's stuck, ask the user.

## Report

End-of-turn summary (1–3 sentences):
- Tests added (count + files).
- Final status (pass/fail + command used).
- Anything skipped or flagged (out-of-scope failures, gaps noticed).

Do NOT commit. Do NOT push. Leave staging clean for the user to review.

## Rules

- **Session-scoped.** Only test what changed this session. No backfilling unrelated coverage.
- **Isolated execution.** Test runs go through a subagent so output doesn't pollute main context.
- **Real fixes only.** No skipped tests, no loosened asserts, no swallowed errors.
- **Stop after 3 rerun cycles.** If it's still red, the user needs to weigh in.
- **No commit.** Hand back a clean working tree with new/updated tests staged-or-not per existing convention.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the 1–3 sentence "Report" step.
