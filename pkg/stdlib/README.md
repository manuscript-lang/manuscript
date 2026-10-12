# Standard-library declarations

The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Go supplies the native implementations; integration tests check that their calling signatures agree with the Manuscript declarations.

## Which file defines what?

- The `.ms` files define the type schemas and public API.
- `bindings.json` maps source identities to native representations and dispatch names. It does not define type schemas.
- `intrinsics.ms` contains private operation declarations for primitive receivers and the universal `toString()` method.
- The heterogeneous `parallel` call is marked in its source module and needs special compiler handling.

These files use a trusted declaration-only parser mode. Native functions and opaque types need no Manuscript body here. Native `impl` blocks declare their method signatures without bodies, and `bindings.json` maps each receiver/contract/method identity to native dispatch. The checker verifies the ordinary implementation rules and native signatures. Application source still needs the usual bodies and type definitions.

## Editor navigation

Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.

Run `ms stdlib <directory>` to export the exact pinned source files for an editor that needs documents on disk. These APIs provide navigation data; an editor integration must supply its own LSP server and transport.

For user-facing imports and API behavior, see the [standard-library guide](../../documentation/standard-library/_index.md).

Filesystem, OS/process, path, and timer contracts are described in the [host package guide](../../documentation/standard-library/packages/node-host.md). The Node.js 24 coverage inventory includes exported APIs and returned handle operations; native signature validation, offline Node path/glob fixtures, and compiled CLI tests keep the mapping reviewable. Platform helpers in `internal/hostos/` are bundled with native dependency sources.

Time and scheduling share `@std/time.ms`: ordinary `sleep`, concurrent `after`/`every`, and one scoped `Timer`. Scheduler yielding is in `@std/tasks.ms`; JavaScript Promise and event-loop forms are documented as compositions rather than duplicated API families.
