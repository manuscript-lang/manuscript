# Standard-library declarations

The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Go supplies the native implementations; initialization checks that their calling signatures agree with the Manuscript declarations.

## Which file defines what?

- The `.ms` files define the type schemas and public API.
- `bindings.json` maps source identities to native representations and dispatch names. It does not define type schemas.
- `intrinsics.ms` contains private operation declarations for primitive receivers.
- The heterogeneous `parallel` call is marked in its source module and needs special compiler handling.

These files use a trusted declaration-only parser mode. Native functions and opaque types need no Manuscript body here. Application source still needs the usual bodies and type definitions.

## Editor navigation

Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.

Run `ms stdlib <directory>` to export the exact pinned source files for an editor that needs documents on disk. These APIs provide navigation data; an editor integration must supply its own LSP server and transport.

For user-facing imports and API behavior, see the [standard-library guide](../design/standard-library/_index.md).
