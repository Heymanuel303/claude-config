---
description: Write tests for the changes made in the current session. Runs the suite in an isolated subagent. Only writes tests — never touches production code. If a test exposes a genuine bug, it halts and reports instead of fixing.
model: sonnet
---

Write tests covering work done earlier in this session, then drive the *tests* to green — by fixing the tests, never the code under test. This command writes tests only. If a test surfaces a genuine defect in the production code, **stop everything and report it** — do not fix it here. Invoked like:

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

## Triage failures — never edit production code

When the agent reports failures, read each failing test + the code under test, then classify each failure. **You may only ever edit test files.** Production/source code is off-limits in this command — full stop.

1. **Test wrong** (bad expectation, stale mock, missing setup, wrong import, my own test bug) → fix the test.
2. **Code wrong** (the test is correct and the production code genuinely misbehaves — regression, logic error, contract violation, unhandled case) → **STOP EVERYTHING.** Do not fix the code. Do not paper over it by weakening the test. Halt the command and report (see "Halt & report").

If you can't tell which side is wrong, treat it as **Code wrong** and halt — surfacing a real problem is the priority, and a false alarm is cheaper than silently editing source or hiding a bug.

Never, under any circumstances:
- Edit production code to make a test pass.
- Loosen / delete an assertion, skip / mark-as-skipped, or catch-and-swallow to turn a genuine failure green.
- Add retries or timing hacks for flakiness — find the real cause; if it's in the code, halt and report.

## Halt & report

When a failure is (or might be) a genuine code defect:

1. Stop immediately — no further test writing, no fixes, no reruns.
2. Report, prominently:
   - **What's wrong** — the defect in the production code, in one or two sentences.
   - **Evidence** — failing test name + `file:line`, the assertion that failed, expected vs actual.
   - **Where** — the production `file:line` you believe is at fault.
   - **Scope of tests already written** — so the user knows what exists.
3. Hand back to the user. Do not proceed until they decide.

## Rerun

Only rerun when the fix was to a **test** (never to production code). Re-delegate the same execution agent (fresh `Agent` call, same brief) after fixing tests. Repeat fix-test → rerun until:

- Overall PASS, or
- A failure resolves to a genuine code defect → **Halt & report** (do not keep looping), or
- Three rerun cycles with the same failure → stop, report what's stuck, ask the user.

## Report

End-of-turn summary (1–3 sentences):
- Tests added (count + files).
- Final status (pass / fail / **halted on code defect**).
- If halted: the one-line "what's wrong" + pointer to the "Halt & report" details above.
- Anything skipped or flagged (out-of-scope failures, gaps noticed).

Do NOT commit. Do NOT push. Leave staging clean for the user to review.

## Rules

- **Tests only.** This command writes and fixes tests. It NEVER edits production code — not to pass a test, not "while I'm here."
- **Genuine defect → halt.** If a correct test exposes a real bug in the code, stop everything and report it. Don't fix it, don't hide it. Ambiguous → treat as a defect and halt.
- **Session-scoped.** Only test what changed this session. No backfilling unrelated coverage.
- **Isolated execution.** Test runs go through a subagent so output doesn't pollute main context.
- **No cheating green.** No skipped tests, no loosened asserts, no swallowed errors, no flakiness hacks.
- **Stop after 3 rerun cycles.** If it's still red, the user needs to weigh in.
- **No commit.** Hand back a clean working tree with new/updated tests staged-or-not per existing convention.

## Output style

- Brief. No preamble, no recap, no chatter.
- Bullet points over prose.
- Lead with the answer; cut everything that isn't actionable.
- Questions (if any): one line each, batched in a single `AskUserQuestion`.
- No closing summary beyond the 1–3 sentence "Report" step.
