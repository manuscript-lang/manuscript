---
name: language-design-taste
description: Apply Chinmay's design preferences when proposing or reviewing programming languages, standard libraries, runtimes, compilers, and developer tooling, especially Manuscript.
---

# Language design taste

- Optimize for AI writing code and humans understanding it: readable source, visible dependencies, clear system boundaries, and explainable execution flows.
- Prefer a few consistent, composable concepts. Before adding syntax, types, or rules, show the concrete problem and whether an existing mechanism can solve it.
- Use familiar names and syntax: `fn`, `type`, `String`, grouped imports, and JavaScript-style destructuring. Name arguments for multi-parameter calls; allow omitted labels for single-parameter calls. Favor one obvious spelling over clever alternatives.
- Make public contracts explicit and infer local details. For Manuscript, use explicit `impl` relationships and contract conversions; avoid accidental conformance and invisible coercions.
- Keep intrinsics, compiler bounds, and ambient names small. Make standard types, utilities, and concurrency APIs explicitly importable; runtime support does not require a language keyword.
- Keep one function kind; ordinary functions may suspend. Execution is sequential unless concurrency is explicitly requested through APIs such as `parallel`, bounded mapping, or `Background`.
- Keep expected failures as values. Preserve operation return types rather than silently flattening or rewriting `Result`; distinguish domain errors, cancellation, and programming faults.
- Prefer garbage-collected references and lexical `with` cleanup through `Closeable` over general moves, borrows, and consuming closures. Specify cleanup on every exit and runtime behavior after close.
- Treat sharing, resource lifetime, and work lifetime as separate guarantees. Keep `Shareable` compiler-verified and equality/hashing derived in Manuscript; capture or aliasing must not invent guarantees.
- Pass external authority explicitly through capabilities. Imports provide declarations; obtaining files, network access, or clocks requires authority. Keep internal handles and authority construction controlled.
- Choose an implementation you can explain end to end. For Manuscript, favor straightforward Go lowering and its runtime; keep build speed, native execution, and source-level debugging practical.
- Check designs against real CLIs, services, and servers: bounded work, streaming and backpressure, shared state, cancellation, and shutdown. Resolve essential semantics without adding machinery for speculative cases.
- Derive diagrams and tooling from typed source. Write terse, technical docs with concrete signatures and examples; give each rule one home, link to it, and name unresolved decisions plainly.

