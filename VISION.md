# Manuscript: The Language for the Agentic Era

**Manuscript is a programming language designed for agents to write and humans to understand.** Its design brings agent behavior, token efficiency, human readability, and precise program analysis together from the start.

## The shift

Software development is changing. Coding agents are moving from suggesting snippets to producing substantial parts of applications. As that happens, the central question becomes not only how capable the models are, but how well the languages and tools let agents build useful software—and let people understand what they built.

Most of today’s languages and ecosystems were shaped around human authorship and decades of accumulated design decisions. Models are getting better at using them, but large codebases, intricate syntax, and slow read–edit–evaluate cycles still create friction for both agents and people.

Manuscript begins with a different premise: if agents will write much of the code, we can design the language itself around that way of working. The language is a foundational part of the stack. Context systems and agent frameworks can help, but they still have to carry the complexity of the language they operate on. A language that is simple and regular by design can reduce a large share of that friction at its source.

## Why Manuscript

Manuscript aims to make agent-driven development feel natural from the first draft through review and deployment. Its central promise is a language that agents can produce confidently and humans can understand without having to hold an entire implementation in their heads.

That promise rests on a small, composable core: familiar ideas such as types, functions, and arithmetic; minimal syntax; and little encouragement for clever syntactic techniques that hide intent. Fewer concepts give agents less to learn and give people less incidental complexity to work through. A regular language is also easier for tools to analyze, explain, and represent faithfully.

The language and toolchain are being shaped through realistic work with frontier coding agents. We observe where agents get stuck, capture the failures and friction, and use that evidence to improve defaults, diagnostics, and workflows. Compiler messages should do more than report failure: they should be structured for tools and agents to consume, while giving actionable next steps.

### Token efficiency with readability and analysis

Agents spend context on source, APIs, diagnostics, and repeated repair attempts. Manuscript aims to reduce that cost across the whole development loop. Compact syntax, a small conceptual core, concise API discovery, and actionable feedback should let more useful work fit in the available context.

Token efficiency must preserve meaning. We want code that is economical to generate and read while remaining clear to people and tractable for static analysis. We measure agent token use and outcomes, and use the evidence to refine the language rather than assuming brevity alone makes a design better.

## Where things stand

Manuscript is in alpha. The capabilities below describe current source; published archives may lag behind. The longer-term vision remains the direction:

- **A small, regular language.** A simple type system with generics, no `any` escape hatch and no runtime reflection API keeps types visible to compiler analysis. It includes `:=`/`var`, nominal records (`type`) and tagged unions (`enum`), exhaustive `match`, `Optional`, `Result` with `try`, generics, `impl` blocks, and sized numerics (`Int8` to `Int64`, `Float32`). Indented blocks, `fn` declarations and explicit imports give programs a consistent shape (`fn add(a: Int, b: Int) Int:`).
- **Ownership without a collector.** Values have one owner, move at their last use and are dropped deterministically; `var` marks mutation, `.clone()` marks copies, borrows are lexical, and a scope closes the resources bound in it.
- **Structured concurrency, no async.** `promise(fn: ...)` starts concurrent work on a thread the runtime picks, and `wait()` takes its result; streams are pulled lazily. A promise only reads what it captures; changes travel to the owner over a `pipe`. See [concurrency](documentation/core-language/concurrency/_index.md) for coordinating work, cancellation and cleanup.
- **Native code with reproducible measurements.** The Rust compiler emits native code through Cranelift or LLVM; the runtime and standard library are embedded in `ms`. [`bench/perf`](bench/perf/README.md) records kernel, JSON, HTTP and worker results, each tied to a revision, machine and reproduction command. They show where Manuscript performs well and where work remains.
- **One command for the development loop.** `ms` checks, formats, lints, tests, builds and profiles. Builds reuse cached or locally configured linking tools; see [build setup](documentation/developer-tooling/how-it-works.md#build-tools-and-local-setup).
- **Feedback agents can act on.** Diagnostics read `cause; fix`, name the Manuscript spelling for habits from other languages, and carry machine-applicable repairs that `ms check --fix` applies. `--json` output from `check`, `lint`, `test`, `run`, `build` and `inspect` reports results and faults as data; `ms search_symbol`, `ms guide`, `ms verify`, `ms review` and `ms diagram` give deterministic views of a program and of a change.
- **Editor and profiling support.** A language server, a VS Code extension, and native sampling profiles with source attribution. Native builds emit DWARF line tables for source lookup.
- **A measured loop.** The [agent benchmark](bench/agent/README.md) runs the same challenges in Manuscript, Go, TypeScript and Rust with hidden tests. The [October 22 run](bench/agent/results/summary-2026-10-22.md) passed 10 of 10 small challenges in Manuscript, with one trial per challenge; first-build success and source size relative to TypeScript remain targets for improvement.

Still ahead: a broader library ecosystem, external adapters, incremental frontend compilation, and the deployment story beyond a single binary.

## The five-to-seven-year vision

Over the next five to seven years, Manuscript aims to become a compelling default for building software with agents: a language and development environment that covers the needs of everyday applications so a team can start with Manuscript and stay productive as its software grows.

That means aiming to support a broad range of software, including server-side applications, command-line tools, web servers, network services, and the libraries those applications need. The ambition is not simply to make agents capable of writing Manuscript. It is to make Manuscript and its ecosystem capable enough that agent-driven teams do not need to reach for another language to get their work done.

In that future, agents handle more of the implementation while people guide the work and inspect its results. Manuscript should make that partnership work exceptionally well: agents can create and revise software through a tight, informative development loop; people can understand the program through readable code and clear representations; and the same coherent toolchain can help take it from development to a deployable artifact.

The goal is a single environment where agents and people can reliably build, understand, check, and ship software. “Manuscript is the no-brainer choice for agent-driven development” is the aspiration. Earning that choice means meeting real application needs, providing a useful library ecosystem, reducing correction cycles, and making software easier to inspect.

## What that future should make possible

### A language agents can work with directly

The language should make common software tasks expressible with a small set of predictable constructs. Agents should be able to form a useful first draft, understand compiler feedback, and make targeted corrections rather than repeatedly fighting hidden language complexity.

### A language people can inspect

As agents write more code, people need practical ways to understand behavior and structure without reading every line. Manuscript’s simplicity makes it possible to derive accurate views directly from code, and `ms diagram` and `ms review` already do so for call graphs and the semantic effect of a diff. `ms diagram ms.toml --format html` packages source, checked type hints and connected views into one offline file. Readers can follow calls, inspect ownership and navigate a diff overlay directly from the code map.

The map describes checked source relationships; tests and profiling complement it with evidence from execution.

### A trustworthy development loop

When agents produce code, the system that helps people evaluate it should provide evidence independent of the code-generating step. Manuscript aims to make that possible through a small language, structured compiler output, and deterministic tools such as `ms verify`, `ms inspect`, and `ms review`.

Tests, domain knowledge and human review build on those compiler checks and diagrams. Clear source and inspectable evidence help people make informed decisions about software produced with agents.

### A coherent path from code to deployment

The Manuscript experience brings the essential development tools together: compiling, building, testing, and profiling ship in one `ms` binary, and `ms build` produces a standalone native executable. The work ahead is making deployment as seamless as the development loop, so these pieces feel like one workflow rather than a collection of unrelated tools.

Keeping the language core small matters. Manuscript has no special asynchronous syntax, so programs use functions and receive values. Promises, streams, pipes and child processes build on those ordinary calls.

### An ecosystem agents can help expand

Historically, a language’s reach has depended heavily on the libraries and integrations available in its ecosystem. Coding agents change the cost of filling gaps: they can help create or translate a needed library when a useful implementation exists elsewhere. This creates room to start with a coherent language and toolchain rather than making interoperability with every older language the central design goal.

That is an opportunity, not an assumption that ecosystem challenges disappear. Manuscript’s long-term usefulness depends on making it practical to build the applications people need and to grow a dependable collection of libraries around them.

## Principles guiding the work

1. Design for agent generation and human understanding together. Code should be straightforward to produce and straightforward to review.
2. Keep the core language small and regular. Prefer familiar, composable concepts over a growing collection of special cases.
3. Put language design at the foundation. Improve the conditions agents work in, rather than relying only on systems layered around language complexity.
4. Make feedback actionable and structured. Compiler and tool messages should help people and agents decide what to do next.
5. Make programs inspectable from their source. Build diagrams and other views from deterministic analysis wherever possible.
6. Learn from actual agent use. Exercise agents on realistic applications, measure outcomes and token use, record where they struggle, and improve the language and tools based on what happens.
7. Optimize context use without sacrificing readability or analysis. Keep source and tool output economical while preserving the information needed to understand and verify a change.
8. Treat the toolchain and ecosystem as part of the language. Compilation, debugging, profiling, libraries, and deployment all contribute to whether Manuscript can serve real projects.


## What success looks like

Manuscript succeeds when teams using agents can build a wide range of useful software with less friction; when people can understand and inspect what agents produce; and when the language, tools, and ecosystem make Manuscript a natural first choice for agent-driven development.

The long-term vision is not just a new syntax. It is a foundation for software development in which agents can do more of the implementation, people retain a clear view of the result, and the language itself makes that collaboration work better.
