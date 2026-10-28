---
name: language-design-taste
description: Apply Chinmay's design preferences when proposing or reviewing programming languages, standard libraries, runtimes, compilers, and developer tooling, especially Manuscript.
---

# Language design taste

- Optimize for AI writing code and humans understanding it: readable source, visible dependencies, clear system boundaries, and explainable execution flows.
- Prefer a few consistent, composable concepts. Before adding syntax, types, or rules, show the concrete problem and whether an existing mechanism can solve it.
- Use familiar names and syntax: `fn`, `fn`, `type`, `String`, `import {A, B} from "p"`, and destructuring. Allow positional invocation with optional labels, binding unlabeled arguments by position, never by variable name, and preserving written evaluation order. Favor one obvious spelling over clever alternatives.
- Make public contracts explicit and infer local details. For Manuscript, use explicit `impl` relationships and contract conversions; avoid accidental conformance and invisible coercions.
- Keep intrinsics, compiler bounds, and ambient names small. Keep `Optional`, `Result`, `Error`, `List`, `Map`, `Set`, their public API support types `CollectionError`, `ListEntry`, `MapEntry`, `MissingValue`, and the alternative cases in the source-backed prelude. Use one path for canonical prelude types: reject redundant standard imports and reject application declarations or imports that reuse the names. Other standard types and utilities remain explicitly importable. Runtime support does not require a language keyword.
- Keep one function kind; ordinary functions may block. Execution is sequential. Concurrency was removed pending a ground-up redesign; do not restore it or removed concurrent collection-mapping helpers without a new user direction.
- Keep expected failures as values. Preserve operation return types rather than silently flattening or rewriting `Result`; distinguish domain errors, cancellation, and programming faults.
- Never show `match` as a way to unwrap a Result in examples, docs, or implementation: use `try`, `if let`, `get(default)`, or `is_ok`/`is_error`/`err`. Compose sequences of calls as `|` flows (`text | try parse | normalize`) instead of nesting calls or naming single-use temporaries.
- Keep success paths flat with compatible `try` calls. Nested `match` is an anti-pattern: use an early-exit payload binding or a small helper when further case handling is needed. Keep examples small and focused; avoid contrived domain models or helper layers added only to make an example work.
- Prefer garbage-collected references and lexical `with` cleanup through `Closeable` over general moves, borrows, and consuming closures. Specify cleanup on every exit and runtime behavior after close.
- Keep ordinary records and collections as owned values: mutation requires `var`, borrows obey exclusivity, and `.clone()` makes an explicit deep copy; the `Clonable` bound lets generic code keep a value it only borrows. Do not clone native resource handles.
- Prefer methods to free functions: put an operation on the type it acts on, and add a free function only when no single receiver fits (Chinmay's preference). `|` flows still compose the free functions that remain.
- Treat sharing, resource lifetime, and work lifetime as separate guarantees. Values may be passed freely without sharing bounds. Keep a local Queue single-threaded and an owned value (a copy is independent, like Deque and List); native services retain their lifecycle synchronization. Keep equality/hashing as explicit interfaces with built-in value implementations.
- Expose standard host services through explicitly imported accessors and keep application entrypoints parameterless. Use ordinary capability parameters where they improve composition or testing. Do not impose per-function authority declarations or manifest permission enforcement without a new user direction.
- Choose an implementation you can explain end to end. For Manuscript, favor straightforward lowering to MIR and Cranelift and a small runtime; keep build speed, native execution, and source-level debugging practical.
- Speed is a goal. Generated code need not mirror source structure: the language is designed to lower cheaply (`try` returns an error value, `Optional` and `Result` stay typed), and the target is parity with hand-written native code. Validate the benefit by measurement before building structural machinery.
- Keep syntax and standard APIs as simple as possible and document how to use each new standard type with a class comment and example. Keep this repository about Manuscript alone: no Node.js, JavaScript, or Go parity documentation.
- Check designs against real CLIs, services, and servers: bounded work, streaming and backpressure, shared state, cancellation, and shutdown. Resolve essential semantics without adding machinery for speculative cases.
- Derive diagrams and tooling from typed source. Write terse, technical docs with concrete signatures and examples; give each rule one home, link to it, and name unresolved decisions plainly.
