# Standard-library declarations

The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Modules with ordinary function or implementation bodies are written in Manuscript and checked and lowered with each importing program. Go supplies the native implementations for declaration-only modules; integration tests check that their calling signatures agree with the Manuscript declarations.

## Which file defines what?

- The `.ms` files define the type schemas and public API.
- `bindings.json` maps function, receiver-operation, and implementation identities directly to native dispatch. It also records method-specific receiver requirements, such as `Equal` for list searches and `String` for list joining; it does not duplicate operation signatures or type schemas.
- `intrinsics.ms` contains private operation declarations for primitive receivers and the universal `toString()` method.
- Native receiver signatures appear once, on their type or intrinsic interface. TaskGroup and Task[T] use ordinary generic declarations; no private free-function declarations are needed for their implementations.

These files use ordinary Manuscript syntax. Runtime functions and receiver operations have empty function bodies, written with the usual colon, such as `export fn commands() -> Commands:`. Opaque type schemas use empty declarations such as `export type Duration:`. Interface signatures remain signatures, and `bindings.json` maps the declarations to native implementations. The checker verifies implementation rules and native signatures. There is no library-only parser mode or `native` keyword. Ordinary record fields may have default expressions.

Nongeneric native defaults are checked expressions in these declarations. Generated source preparation evaluates omitted defaults before calling the unchanged native ABI; mutable values are created afresh. Existing `Optional[T] = none` adapters keep their native path, including generic native declarations. Other native generic expression defaults are rejected until their substitution contract is implemented; source generic defaults remain supported. Do not add another default schema to `bindings.json` or the runtime.

This slice permits expression field defaults on ordinary records. Opaque native constructors retain their existing defaults until delivery/disposal is designed. Standard interface expression defaults are restricted to closed literals or bytes converted from literal text, so preparing inherited defaults before an implementation's own defaults cannot reorder visible effects or read a still-missing parameter. Dependent/effectful inherited defaults need one combined ordered prologue before that restriction is expanded. Recursive native default expansion is rejected during lowering; use a source wrapper for recursive defaults.

Direct calls supplying every new expression default keep the original dispatch, including old `none` omission slots. Stateless free-function and ordinary-record default callables are cached through the existing Lazy mechanism; default expressions and mutable storage are still evaluated per call. Receiver-bound callables retain their captured receiver and have a runtime slot check.

Modules with executable bodies use the ordinary checker and need no entries in `bindings.json`. Imports include their reachable source implementations once, with the same public visibility and type identities as application modules.

## Editor navigation

Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.

Hover documentation lives in contiguous `#` comments immediately above a public declaration or operation. The LSP renders this text as Markdown beneath the checked Manuscript signature. Keep the opening sentence direct, then describe behavior that is not clear from the signature: units, defaults, limits, mutation, end-of-stream behavior, and expected errors. Inline Markdown such as code spans is supported.

The generated Markdown/JSON reference also reads comments above fields, cases, and receiver/implementation operations. Keep each block at the member's indentation; a blank line detaches it. JSON preserves the original string arrays and adds structured `members` descriptions. Document case payloads by placing each parameter and its comment on an indented line inside the parentheses; a case description does not describe its fields implicitly.

`make docs` and `make docs-check` report description counts and enforce the description gate. `make docs-coverage` writes the complete inventory to `.artifacts/stdlib-doc-coverage.json`, including prelude aliases. Presence and structural quality are separate counts: empty text, placeholders, very terse labels, and name/kind restatements fail quality checks. Review each description against source/native behavior; passing structural checks cannot prove semantic accuracy or measure a separate tutorial's coverage.

`pkg/tooling/docgen/description_backlog.json` records exact existing gaps during #176's sweep. This temporary list only shrinks: new gaps fail, invalid prose cannot use it, and described/removed entries make the old key stale. It is not an internal/generated exemption. Public synthetic primitive entries require descriptions too. Private `ValueOperations`/`CloneOperations` are implementation declarations; their universal calls have canonical call rules rather than becoming importable interfaces. No blanket public-description exemption is supported.

Run `ms stdlib <directory>` to export the exact pinned source files for an editor that needs documents on disk. These APIs provide navigation data; an editor integration must supply its own LSP server and transport.

For user-facing imports and API behavior, see the [standard-library guide](../../documentation/standard-library/_index.md).

Filesystem and path contracts are described in the [filesystem guide](../../documentation/standard-library/filesystem.md); [system](../../documentation/standard-library/system.md), [process](../../documentation/standard-library/process.md), and [scheduling](../../documentation/concurrency/scheduling.md) have their own guides. Platform helpers in `internal/hostos/` are bundled with native dependency sources.

Time values and sequential `sleep` live in `@std/time.ms`. `@std/tasks.ms` owns `Scheduler`, which manages immediate, delayed, and repeating work through one operation-ID lifecycle, plus TaskGroup, Task[T], cancellation checks, and scheduler yielding. Limits and deadlines use optional values; receiver operations are the single public API for existing data.
