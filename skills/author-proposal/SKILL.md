---
name: author-proposal
description: Write a Manuscript design proposal grounded in the existing language, with checked syntax examples, touched components, and the smallest design that works.
---

# Author a proposal

Use whenever you write or revise a design proposal. Store it in the repo as `proposals/<kebab-name>.md` (in the change's PR or its own); update it in place and record the decision in Status. This includes the short proposal AGENTS.md requires before a cross-package change. Follow [manuscript-change](../manuscript-change/SKILL.md) and [language-design](../language-design/SKILL.md).

The default design is no new syntax, no new type, and no new keyword. Earn each addition.

## Step 1: learn the language before designing

Do this before writing any section. A proposal that invents syntax or names without it is rejected.

- Run `ms guide` and read the relevant pages in `documentation/core-language/` (types, functions, control flow, errors, modules, cleanup) and `documentation/glossary.md`.
- Read `crates/DESIGN.md` for the pipeline, ABI, and recorded decisions, and `wiki/` for the domain (see `wiki/index.yml`).
- Find existing idioms with `ms search_symbol <words>` and read the nearest `stdlib/*.ms` modules. Copy their naming, argument order, error handling, and ownership style.
- Read `proposals/` for decisions already made (names, direction, rejected ideas). A past proposal is a record of decisions, not a source of syntax; verify anything it shows against the guide.
- Never contradict a stated user decision (spelling, casing, names, scope). Quote the decision in Status; if the design needs to reverse one, put it in Open questions, do not assume.
- Do not import syntax from other languages (guards, tuples, records, static methods, lowercase generics, and so on). If Manuscript lacks a construct, the design works without it or proposes it as its own explicit, justified language change.
- Reuse existing names. A new name must be plain and say what it does; avoid metaphors and paired terms that need explaining (near/far).

## Step 2: write it

Target 60 to 100 lines; past 120, split or cut. Every line must change the decision or tell the implementer what to build. Technical and scannable: one fact per bullet, bullets of one or two lines, no paragraph over two sentences. Name crates, files, functions, and types exactly. Label claims as measured (command, commit, number), verified (`file:line`), or hypothesis.

Sections, in order. A small change uses Summary, Problem, Design, Components, Alternatives.

1. **Summary**: 3 bullets: problem, change, decision requested.
2. **Status**: one line: proposal, approved, or implemented; date; commit checked. Quote the user's direction only when it constrains the design. No review logs, changelogs, or progress notes; the review outcome is one line.
3. **Problem**: the observable failure or cost, with one minimal repro (at most 10 lines) or one measurement. Further cases get one bullet each, with a pointer to the test or fixture. Non-goals only if a reader would assume them.
4. **Design**: the rule, stated once.
   - Syntax and API as short `.ms` examples (accepted and rejected, with the exact diagnostic) and before/after only for programs that change.
   - Semantics for ownership, errors, cancellation, and edge cases, one bullet each.
   - A diagram only where data flow, lifetimes, layout, or stage order matter. Never restate a bullet list.
5. **Components touched**: a table of components that change, with the test for each. Add "unchanged" only for a component a reader would expect to change.

   | Component | Change | Test |
   | --- | --- | --- |
   | `crates/ms-check` | new rule, diagnostic | conformance reject case |

6. **Alternatives**: do nothing, the smallest version, and the real runner-up, one or two lines each with the evidence it lost. Drawbacks of the chosen design only if they change the decision.
7. **Stages**: one line per stage with its check; each lands green. Omit when there is one stage.
8. **Open questions**: only where the language or user-visible behavior changes, each with a recommendation.

Omit a section by leaving it out. Add nothing beyond these.

Cut on sight:
- history of how the idea evolved, rejected syntax that nobody proposed, and restated context from other proposals (link instead);
- full programs where an excerpt shows the point, and tables that repeat prose;
- implementation detail the code will show (function-by-function walkthroughs, line-number tours); keep the contract and the invariants;
- stage detail beyond the check that gates it.

Once implemented, cut the proposal to Summary, Status, and the decisions that are not obvious from the code, and move durable lessons to `wiki/`.

## Step 3: check the syntax

Every `.ms` example must pass `ms check` against current main before the proposal is committed.

- Build `ms` from main (`cargo build --release --locked -p ms-cli`), put each example in a scratch project, and run `ms check`.
- For APIs or syntax the proposal adds, check against stubs: write the declaration as a stdlib-style `fn` with a placeholder body so the call sites type-check. Mark only the stubbed lines.
- A rejected example must fail with the quoted diagnostic. Paste real output, not recollection.
- If an example needs syntax that does not check, it is a language change: say so in Summary and Open questions.

## Step 4: simplify, then review

- List every new concept, name, flag, type, keyword, runtime entry point, and pass. For each: can an existing mechanism cover it? Can the first version drop it? Delete what cannot be justified, and record what was removed.
- Prefer one rule over two; prefer a stdlib function over syntax; prefer a smaller first stage.
- Keep Linux, macOS, and Windows at parity; never propose disabling a test on a platform.
- Run the skeptical review in [AGENTS.md](../../AGENTS.md) on the finished file, giving the reviewer the file rather than your conclusion. Apply its changes and record the verdict in one line of Status.
- Last, reread for length: delete every bullet that does not change the decision or the build.
- Run `make repo-check`; keep `match` flat in examples.
