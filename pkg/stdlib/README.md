# Standard-library declarations

The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Modules with ordinary function or implementation bodies are written in Manuscript and checked and lowered with each importing program. Go supplies the native implementations for declaration-only modules; integration tests check that their calling signatures agree with the Manuscript declarations.

## Which file defines what?

- The `.ms` files define the type schemas and public API.
- `bindings.json` maps function, receiver-operation, and implementation identities directly to native dispatch. It also records method-specific receiver requirements, such as `Equal` for list searches and `String` for list joining; it does not duplicate operation signatures or type schemas.
- `intrinsics.ms` contains private operation declarations for primitive receivers and the universal `toString()` method.
- Native receiver signatures appear once, on their type or intrinsic interface. TaskGroup and Task[T] use ordinary generic declarations; no private free-function declarations are needed for their implementations.

These files use ordinary Manuscript syntax. Runtime functions and receiver operations have empty function bodies, written with the usual colon, such as `export fn commands() -> Commands:`. Opaque type schemas use empty declarations such as `export type Duration:`. Interface signatures remain signatures, and `bindings.json` maps the declarations to native implementations. The checker verifies implementation rules and native signatures. There is no library-only parser mode or `native` keyword. Ordinary record fields may have default expressions.

Modules with executable bodies use the ordinary checker and need no entries in `bindings.json`. Imports include their reachable source implementations once, with the same public visibility and type identities as application modules.

## Editor navigation

Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.

Run `ms stdlib <directory>` to export the exact pinned source files for an editor that needs documents on disk. These APIs provide navigation data; an editor integration must supply its own LSP server and transport.

For user-facing imports and API behavior, see the [standard-library guide](../../documentation/standard-library/_index.md).

Filesystem and path contracts are described in the [filesystem guide](../../documentation/standard-library/filesystem.md); [system](../../documentation/standard-library/system.md), [process](../../documentation/standard-library/process.md), and [scheduling](../../documentation/concurrency/scheduling.md) have their own guides. Platform helpers in `internal/hostos/` are bundled with native dependency sources.

Time values and sequential `sleep` live in `@std/time.ms`. `@std/tasks.ms` owns `Scheduler`, which manages immediate, delayed, and repeating work through one operation-ID lifecycle, plus TaskGroup, Task[T], cancellation checks, and scheduler yielding. Limits and deadlines use optional values; receiver operations are the single public API for existing data.
