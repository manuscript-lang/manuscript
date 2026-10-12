---
name: language-design-taste
description: Apply Chinmay's design preferences when proposing or reviewing programming languages, standard libraries, runtimes, compilers, and developer tooling, especially Manuscript.
---

# Language design taste

- Optimize for AI writing code and humans understanding it: readable source, visible dependencies, clear system boundaries, and explainable execution flows.
- Prefer a few consistent, composable concepts. Before adding syntax, types, or rules, show the concrete problem and whether an existing mechanism can solve it.
- Use familiar names and syntax: `fn`, `type`, `String`, grouped imports, and JavaScript-style destructuring. Use matching-name shorthand or explicit labels for multi-parameter calls; allow omitted labels for single-parameter calls. Favor one obvious spelling over clever alternatives.
- Make public contracts explicit and infer local details. For Manuscript, use explicit `impl` relationships and contract conversions; avoid accidental conformance and invisible coercions.
- Keep intrinsics, compiler bounds, and ambient names small. Make standard types, utilities, and concurrency APIs explicitly importable; runtime support does not require a language keyword.
- Keep one function kind; ordinary functions may suspend. Execution is sequential unless concurrency is explicitly requested through standard APIs. Do not restore removed concurrent collection-mapping helpers.
- Keep expected failures as values. Preserve operation return types rather than silently flattening or rewriting `Result`; distinguish domain errors, cancellation, and programming faults.
- Keep success paths flat with compatible `try` calls. Keep examples small and focused; avoid contrived domain models or helper layers added only to make an example work.
- Prefer garbage-collected references and lexical `with` cleanup through `Closeable` over general moves, borrows, and consuming closures. Specify cleanup on every exit and runtime behavior after close.
- Keep ordinary records and collections mutable. Use explicit shallow `.clone()` for separate data storage; do not introduce mandatory freezing or clone native resource handles.
- Treat sharing, resource lifetime, and work lifetime as separate guarantees. Values may be passed freely without sharing bounds. Keep a local Queue single-threaded and use explicit `Synchronized[T]` guards for shared mutable access and complete updates; native services retain their lifecycle synchronization. Keep equality/hashing as explicit interfaces with built-in value implementations, independent of concurrency.
- Expose standard host services through explicitly imported accessors and keep application entrypoints parameterless. Use ordinary capability parameters where they improve composition or testing. Do not impose per-function authority declarations or manifest permission enforcement without a new user direction.
- Choose an implementation you can explain end to end. For Manuscript, favor straightforward Go lowering and its runtime; keep build speed, native execution, and source-level debugging practical.
- Check designs against real CLIs, services, and servers: bounded work, streaming and backpressure, shared state, cancellation, and shutdown. Resolve essential semantics without adding machinery for speculative cases.
- Derive diagrams and tooling from typed source. Write terse, technical docs with concrete signatures and examples; give each rule one home, link to it, and name unresolved decisions plainly.
