[Wiki](../index.md) › Language

# Language

Syntax, types, imports, removals, language decisions.

Note on memory model: on 2026-10-19 the owner adopted value semantics for the Rust implementation (see [compiler.md](../compiler/index.md) and [ownership notes](../../crates/ms-check/OWNERSHIP.md)). Entries below that speak of shared references, aliasing, or `.clone()` record user decisions made under reference semantics; where they conflict with the ownership notes, the notes and the frozen conformance corpus win, and the conflict is flagged in the entry.

- [Keywords are names after a dot and as field labels](keywords-are-names-after-a-dot-and-as-field-labels.md)
- [Type aliases are transparent and resolved in the checker](type-aliases-are-transparent-and-resolved-in-the-checker.md): `type Name[T] = Type` is another name for a type expression, expanded in `resolve`.
- [Enums declare tagged unions](enums-declare-tagged-unions.md): use `enum` with bare variants; records keep `type`, and legacy syntax receives clear diagnostics.
- [An unsaved overlay cannot replace a dangling source symlink](an-unsaved-overlay-cannot-replace-a-dangling-source-symlink.md): editor overlays may create a file beneath an existing confined directory, but a dangling symlink remains a filesystem entry whose target ide…
- [`Clonable` replaces ad hoc copying in generic code](clonable-replaces-ad-hoc-copying-in-generic-code.md): `Clonable` is a prelude interface whose `value.clone()` returns an independent deep copy, so a generic body can keep a value it only borrows.
- [Compound assignment, counting ranges, and redundant labels](compound-assignment-counting-ranges-and-redundant-labels.md): the user asked to add `+= -= *= /= %=`, a step-1 `range(start, end)`, and removal of redundant argument labels (October 2026 proposal `struc…
- [Default arguments must not leak across callable replacement](default-arguments-must-not-leak-across-callable-replacement.md): ordinary record fields may have default expressions.
- [Equality and hashing are source interfaces](equality-and-hashing-are-source-interfaces.md): the stdlib revamp explicitly replaces compiler-only equality/hashing bounds with `Equal` and `Hashable` interfaces, and explicit implementat…
- [Error translation does not need a dedicated standard helper](error-translation-does-not-need-a-dedicated-standard-helper.md): remove the specialized Result error-mapping helper and keep domain translation in ordinary functions that test `is_error()` and read `err()`…
- [`extern fn` binds native symbols; planned natives stay labeled](extern-def-binds-native-symbols-planned-natives-stay-labeled.md): `extern fn name(...) T` declares a bodiless function whose symbol is its Manuscript name, linked with `--link` (#1136, #1138).
- [`for` and lambda parameters destructure by parser desugar](for-and-lambda-parameters-destructure-by-parser-desugar.md): list and record patterns after `for` and in `fn [a, b]:` become a hidden name plus a synthetic `:=`; formatter and position-based passes must skip it.
- [`for` walks `Iterator[T]` by expansion, not a new loop kind](for-walks-iterator-t-by-expansion-not-a-new-loop-kind.md): `Iterator[T]` (`var def next() -> T?`, `@std/core.ms`) makes a type iterable.
- [Immutable bindings are `:=`; `let` and `let (` are removed](immutable-bindings-are-colon-assign-and-let-is-removed.md): `x := e` immutable, `var x = e` mutable, `x: T = e` typed, `if v := opt:`, no `let (` groups.
- [Interface conversion rules](interface-conversion-rules.md): Implicit interface conversion, no construction syntax, borrowed values becoming views.
- [Infer local callback signatures from context](infer-local-callback-signatures-from-context.md): the user explicitly permits callback parameter and result inference.
- [Invalid bounds must not survive recovery](invalid-bounds-must-not-survive-recovery.md): reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph.
- [Keep short bodies available without a second function kind](keep-short-bodies-available-without-a-second-function-kind.md): the user requested a terse language with single-line functions and conditions.
- [Local implementations must remain selected across module boundaries](local-implementations-must-remain-selected-across-module-bou.md): accepting an implementation for an imported source type requires more than relaxing receiver ownership.
- [Match is uniformly a value expression; indexing returns the element](match-is-uniformly-a-value-expression-indexing-returns-the-e.md): when addressing familiar-language friction, the user explicitly chose a single `match` expression form rather than retaining a separate statement form.
- [Function types carry `var` parameters](function-types-carry-var-parameters.md): `fn(var List[Int]) Unit` is a distinct type; a named function with `var` parameters is a value of it, lambdas declare `var` parameters, and calls through the value mark the argument `var`.
- [Method values borrow their receiver](method-values-borrow-their-receiver.md): a method value is a closure over its receiver: local, it borrows the receiver's place; escaping, it takes the receiver, moving it at its last use.
- [Methods before free functions](methods-before-free-functions.md): do not add "random" free functions to the standard library or examples; put the operation on the type it acts on.
- [Types stay next to their methods](types-stay-next-to-their-impls.md): a type's receiver methods directly follow its declaration.
- [Module-level constants are use-site evaluations, not stored values](module-level-constants-are-use-site-evaluations-not-stored-v.md): Chinmay approved top-level `let NAME[: T] = <constant expression>` in the #332 thread after the ban was found to have no recorded rationale;…
- [Mutable data uses explicit copying](mutable-data-uses-explicit-copying.md): ordinary record fields and collections are mutable.
- [Ownership vocabulary is own, borrow, move, clone, capture](ownership-vocabulary-is-own-borrow-move-clone-capture.md): five words for code, diagnostics and docs; no lend, consume or clone.
- [No special `get` accessor declarations](no-special-get-accessor-declarations.md): the user rejected the `get name -> Type` accessor syntax merged in #516 (2026-10-16) and asked for ordinary members: observational reads suc…
- [Optional values need presence and extraction methods](optional-values-need-presence-and-extraction-methods.md): the user explicitly rejected relying on `match` for routine Optional handling.
- [Optional and Result `get()` borrow alike; both print as source cases](optional-and-result-get-borrow-and-print-as-source-cases.md): `var x = r.get()` rejected for both; text shows `some(v)`/`none`/`ok(v)`/`error(e)`.
- [Parameterless main and imported host accessors](parameterless-main-and-imported-host-accessors.md): applications export `def main() -> Int` and import the standard services they use.
- [Pipe steps desugar in the parser; a leading `.` or `|` line continues a statement](pipe-steps-desugar-in-the-parser-a-leading-or-line-continues.md): Chinmay chose `|` (not `|>`, `?`, UFCS, or `map_error`) to compose free functions and `?` steps without temporaries; `|` earlier rejected…
- [`print` is the one prelude function](print-is-the-one-prelude-function.md): `print(value)` writes any value as text plus a newline; the prelude lookup now also binds functions from the `core.ms` source twin.
- [Read the current decision before restoring an older design](read-the-current-decision-before-restoring-an-older-design.md): the language rebuild was directed to use the new design on `main`.
- [Errors are plain values with a fixed shape](errors-are-plain-values-with-a-fixed-shape.md): one prelude `Error` record with `message`, `kind` and `details`; no domain types, narrowing or interface.
- [Recursive data; generic applications still stay finite](recursive-data-generic-applications-still-stay-finite.md): direct and mutually recursive tree types, resolving [issue #97](https://github.com/manuscript-lang/manuscript/issues/97) and superseding the…
- [Results borrow parts of their arguments without a marker](results-borrow-parts-of-their-arguments-without-a-marker.md): one owner, no reference counting; primitives copy, everything else borrows, moves or `.clone()`s, and a function returning a part of an argument lends it.
- [Removing a construct includes its surrounding APIs](removing-a-construct-includes-its-surrounding-apis.md): the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests.
- [Result error values do not require Error](result-error-values-do-not-require-error.md): `E` may be any value; `?` needs the identical error type.
- [Result types use `->` (Python-aligned surface)](result-types-use-python-aligned-surface.md): Superseded (2026-10-28): the surface is deliberately distinct from Python again, see [Surface syntax is its own, not Python's](#surface-synt…
- [Source-backed data types belong in the prelude](source-backed-data-types-belong-in-the-prelude.md): the user requested Optional, Result, their related helpers, and Error without imports.
- [Standard and user code share one method syntax](standard-and-user-code-share-one-method-syntax.md): the user required that the standard library, as the reference, use only forms user code can write.
- [String conversion is available on every value](string-conversion-is-available-on-every-value.md): the user requested conversion with `to_string()` on everything.
- [Surface syntax is its own, not Python's](surface-syntax-is-its-own-not-python-s.md): agents slip into Python when the surface looks like Python (the Haiku bench logged 20 capitalized `True`/`False` errors), so the surface now…
- [Grouped imports cover several modules](grouped-imports-cover-several-modules.md): one parenthesized import with `names from "path"` clauses; fmt groups consecutive imports.
- [Syntax improvements need examples across their boundaries](syntax-improvements-need-examples-across-their-boundaries.md): support grouped symbol imports and brace Map literals.
- [Multi-line text is one token that line-based passes must mask](multi-line-text-is-a-token-the-line-passes-must-mask.md): `"""` and `r"""` literals and the formatter placeholder.
- [`T!` and `T?` are type suffixes; there is no `some`](t-and-t-are-type-suffixes-there-is-no-some.md): `T!` is `Result[T, Error]` and `T!E` is `Result[T, E]` (no space before `E`), mirroring `T?` for optionals.
- [Comments are `//` and `/* */`, and blocks are whole-line](comments-are-slash-slash-and-block-comments-are-whole-line.md): `#` is rejected; `//` for lines, non-nesting whole-line `/* */` blocks, one shared doc extractor, and the fixture-header and offset migration traps.
- [Source-location constants](source-location-constants.md): `__LINE__` (Int) and `__FILE__` (String) are checker-known names resolved at the use site; unbound-name "contextual" inference must exclude them.
- [String.view is an explicit borrow; slice stays a copy](string-view-is-an-explicit-borrow-slice-stays-a-copy.md): O(1) substrings are checked borrows like `Bytes.view`, not lowering elision; storing a view needs `.clone()`.
- [`String.split`, `lines` and `chars` lend their receiver](split-lines-and-chars-lend-their-receiver.md): results borrow under the `view` rules; keeping one needs `.clone()`.
- [Write terse Manuscript](terse-manuscript-idioms.md): shortest existing form (`print`, `repeated`, `map`/`filter`, `if` expressions, `is_empty`, multi-line strings); conformance fixtures stay frozen.
- [Optional chaining `?.` is for Optionals only](optional-chaining-is-for-optionals-only.md): `?.` stays an Optional operator; Results and errors use `?` and `match`.
