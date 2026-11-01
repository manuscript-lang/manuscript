[Wiki](../index.md) › Language

# Language

Syntax, types, imports, removals, language decisions.

Note on memory model: on 2026-10-19 the owner adopted value semantics for the Rust implementation (see [compiler.md](../compiler/index.md) and [ownership notes](../../crates/ms-check/OWNERSHIP.md)). Entries below that speak of shared references, aliasing, or `.clone()` record user decisions made under reference semantics; where they conflict with the ownership notes, the notes and the frozen conformance corpus win, and the conflict is flagged in the entry.

- [An unsaved overlay cannot replace a dangling source symlink](an-unsaved-overlay-cannot-replace-a-dangling-source-symlink.md): editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target ide…
- [`Clonable` replaces ad hoc copying in generic code](clonable-replaces-ad-hoc-copying-in-generic-code.md): `Clonable` is a prelude interface whose `value.clone()` returns an independent deep copy, so a generic body can keep a value it only borrows.
- [Compound assignment, counting ranges, and redundant labels](compound-assignment-counting-ranges-and-redundant-labels.md): the user asked to add `+= -= *= /= %=`, a step-1 `range(start, end)`, and removal of redundant argument labels (October 2026 proposal `struc…
- [Default arguments must not leak across callable replacement](default-arguments-must-not-leak-across-callable-replacement.md): ordinary record fields may have default expressions.
- [Equality and hashing are source interfaces](equality-and-hashing-are-source-interfaces.md): the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces, and explicit implementat…
- [Error translation does not need a dedicated standard helper](error-translation-does-not-need-a-dedicated-standard-helper.md): remove the specialized Result error-mapping helper and keep domain translation in ordinary functions that test `is_error()` and read `err()`…
- [`extern fn` binds native symbols; planned natives stay labeled](extern-def-binds-native-symbols-planned-natives-stay-labeled.md): `extern fn name(...) T` declares a bodiless function whose symbol is its Manuscript name, linked with `--link` (#1136, #1138).
- [`for` walks `Iterator[T]` by expansion, not a new loop kind](for-walks-iterator-t-by-expansion-not-a-new-loop-kind.md): `Iterator[T]` (`var def next() -> T?`, `@std/core.ms`) makes a type iterable.
- [Grouped bindings are one-kind blocks, not tuple patterns](grouped-bindings-are-one-kind-blocks-not-tuple-patterns.md): `let (` / `var (` declare several bindings of one kind, one entry per line, closing `)` aligned with the keyword; each entry is an ordinary…
- [Implementing types convert to their interface implicitly](implementing-types-convert-to-their-interface-implicitly.md): a type with a declared `impl I for T` passes wherever `I` is expected; `Error` widening was already implicit and shares the path (`Info.error_source`).
- [Infer local callback signatures from context](infer-local-callback-signatures-from-context.md): the user explicitly permits callback parameter and result inference.
- [Interfaces convert implicitly; construction is removed](interfaces-convert-implicitly-construction-is-removed.md): Status: in flight (PR #1135, not yet on main as of this note).
- [Invalid bounds must not survive recovery](invalid-bounds-must-not-survive-recovery.md): reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph.
- [Keep short bodies available without a second function kind](keep-short-bodies-available-without-a-second-function-kind.md): the user requested a terse language with single-line functions and conditions.
- [Local implementations must remain selected across module boundaries](local-implementations-must-remain-selected-across-module-bou.md): accepting an implementation for an imported source type requires more than relaxing receiver ownership.
- [Match is uniformly a value expression; indexing returns the element](match-is-uniformly-a-value-expression-indexing-returns-the-e.md): when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form.
- [Methods before free functions](methods-before-free-functions.md): do not add "random" free functions to the standard library or examples; put the operation on the type it acts on.
- [Module-level constants are use-site evaluations, not stored values](module-level-constants-are-use-site-evaluations-not-stored-v.md): Chinmay approved top-level `let NAME[: T] = <constant expression>` in the #332 thread after the ban was found to have no recorded rationale;…
- [Mutable data uses explicit copying](mutable-data-uses-explicit-copying.md): ordinary record fields and collections are mutable.
- [No special `get` accessor declarations](no-special-get-accessor-declarations.md): the user rejected the `get name -> Type` accessor syntax merged in #516 (2026-10-16) and asked for ordinary members: observational reads suc…
- [Optional values need presence and extraction methods](optional-values-need-presence-and-extraction-methods.md): the user explicitly rejected relying on `match` for routine Optional handling.
- [Parameterless main and imported host accessors](parameterless-main-and-imported-host-accessors.md): applications export `def main() -> Int` and import the standard services they use.
- [Pipe steps desugar in the parser; a leading `.` or `|` line continues a statement](pipe-steps-desugar-in-the-parser-a-leading-or-line-continues.md): Chinmay chose `|` (not `|>`, `?`, UFCS, or `map_error`) to compose free functions and `try` steps without temporaries; `|` earlier rejected…
- [Read the current decision before restoring an older design](read-the-current-decision-before-restoring-an-older-design.md): the language rebuild was directed to use the new design on `main`.
- [Recover concrete contract receivers through checked matching](recover-concrete-contract-receivers-through-checked-matching.md): a common Error contract must allow generic diagnostics and specific handling without discarding the concrete error.
- [Recursive data; generic applications still stay finite](recursive-data-generic-applications-still-stay-finite.md): direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the…
- [`ref` is removed; results and fields own their value](ref-is-removed-results-and-fields-own-their-value.md): Chinmay asked for `ref` to be removed after the one-borrow model left it as the last lending marker.
- [Removing a construct includes its surrounding APIs](removing-a-construct-includes-its-surrounding-apis.md): the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests.
- [Result's error type is bounded by Error](result-s-error-type-is-bounded-by-error.md): Chinmay required `Result[T, E: Error]`; arbitrary error values (`String`, `Int`, collections) are rejected.
- [Result types use `->` (Python-aligned surface)](result-types-use-python-aligned-surface.md): Superseded (2026-10-28): the surface is deliberately distinct from Python again, see [Surface syntax is its own, not Python's](#surface-synt…
- [Source-backed data types belong in the prelude](source-backed-data-types-belong-in-the-prelude.md): the user requested Optional, Result, their related helpers, and Error without imports.
- [Standard and user code share one method syntax](standard-and-user-code-share-one-method-syntax.md): the user required that the standard library, as the reference, use only forms user code can write.
- [String conversion is available on every value](string-conversion-is-available-on-every-value.md): the user requested conversion with `to_string()` on everything.
- [Surface syntax is its own, not Python's](surface-syntax-is-its-own-not-python-s.md): agents slip into Python when the surface looks like Python (the Haiku bench logged 20 capitalized `True`/`False` errors), so the surface now…
- [Syntax improvements need examples across their boundaries](syntax-improvements-need-examples-across-their-boundaries.md): support grouped symbol imports and brace Map literals.
- [Multi-line text is one token that line-based passes must mask](multi-line-text-is-a-token-the-line-passes-must-mask.md): `"""` and `r"""` literals and the formatter placeholder.
- [`T!` and `T?` are type suffixes; there is no `some`](t-and-t-are-type-suffixes-there-is-no-some.md): `T!` is `Result[T, Error]` and `T!E` is `Result[T, E]` (no space before `E`), mirroring `T?` for optionals.
