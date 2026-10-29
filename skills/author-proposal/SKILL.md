---
name: author-proposal
description: Write a Manuscript design proposal grounded in the existing language, with checked syntax examples, touched components, and the smallest design that works.
---

# Author a proposal

Use whenever you write or revise a design proposal. Store it in the repo as `proposals/<kebab-name>.md` (in the change's PR or its own); update it in place and record the decision in Status. This includes the short proposal AGENTS.md requires before a cross-package change. Follow [manuscript-change](../manuscript-change/SKILL.md) and [language-design-taste](../language-design-taste/SKILL.md).

The default design is no new syntax, no new type, and no new keyword. Earn each addition.

## Step 1: learn the language before designing

Do this before writing any section. A proposal that invents syntax or names without it is rejected.

- Run `ms guide` and read the relevant pages in `documentation/core-language/` (types, functions, control flow, errors, modules, cleanup) and `documentation/glossary.md`.
- Read `crates/DESIGN.md` for the pipeline, ABI, and recorded decisions, and `.experts/` for the domain (see `.experts/index.yml`).
- Find existing idioms with `ms search_symbol <words>` and read the nearest `stdlib/*.ms` modules. Copy their naming, argument order, error handling, and ownership style.
- Read `proposals/` for decisions already made (names, direction, rejected ideas). A past proposal is a record of decisions, not a source of syntax; verify anything it shows against the guide.
- Never contradict a stated user decision (spelling, casing, names, scope). Quote the decision in Status; if the design needs to reverse one, put it in Open questions, do not assume.
- Do not import syntax from other languages (guards, tuples, records, static methods, lowercase generics, and so on). If Manuscript lacks a construct, the design works without it or proposes it as its own explicit, justified language change.
- Reuse existing names. A new name must be plain and say what it does; avoid metaphors and paired terms that need explaining (near/far).

## Step 2: write it

Technical, bulleted, scannable. One fact per bullet, bullets of one or two lines, no paragraph over two sentences. Name crates, files, functions, and types exactly. Label claims as measured (command, commit, number), verified (`file:line`), or hypothesis.

Sections, in order (a small change uses Summary, Problem, Design, Components, Alternatives):

1. **Summary**: 3 to 5 bullets: problem, change, cost, decision requested.
2. **Status**: proposal, approved, or implemented; date; commit checked against; the user's direction, quoted.
3. **Problem**: observable failure or cost with a minimal repro or measurement. Non-goals as bullets.
4. **Design**: the rule, stated once.
   - Syntax and API as `.ms` examples (accepted and rejected, with exact diagnostics) and before/after for changed programs.
   - Semantics for ownership, errors, cancellation, and edge cases, one bullet each.
   - A diagram (mermaid or ASCII) only where data flow, lifetimes, layout, or stage order matter; show before and after when rewiring. Never restate a bullet list.
5. **Components touched**: one row per component, including "unchanged" for any a reader would expect to change.

   | Component | Change | Test |
   | --- | --- | --- |
   | `crates/ms-check` | new rule, diagnostic | conformance reject case |

   Consider: parser, checker, lowering/MIR, codegen, `ms-rt`/ABI, `stdlib/*.ms` and `bindings.json`, formatter, lint, LSP/VS Code, CLI, docs, tests.
6. **Alternatives**: including do nothing and the smallest version, each with evidence for why it lost. Add drawbacks of the chosen design and a line on how comparable languages do it only when that changes the decision.
7. **Staging and verification**: stages that each land green, the check per stage, the go/no-go gate.
8. **Open questions**: options with a recommendation, for the owner, only where the language or user-visible behavior changes.

Omit a section by saying in one line why it does not apply. Add nothing beyond these.

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
- Run the skeptical review in [AGENTS.md](../../AGENTS.md) on the finished file, giving the reviewer the file rather than your conclusion, and record the outcome in Status.
- Run `make repo-check`; keep `match` flat in examples.
