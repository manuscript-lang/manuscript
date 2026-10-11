The `.ms` files in this directory define the standard library's public types,
fields, cases, function signatures, and receiver operations. The compiler reads
these pinned sources directly. Go supplies native implementations, whose ABI
signatures are checked against the Manuscript declarations during initialization.

`bindings.json` maps source identities to native representations and dispatch
names; it does not define the type schemas. `intrinsics.ms` supplies private
operation declarations for primitive receivers. The heterogeneous `parallel`
call remains a compiler intrinsic, marked in its source module.

These files use the trusted library parser's declaration-only mode: native
functions and opaque types need no Manuscript body. Application parsing retains
its normal body and type requirements.

Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt`
for hover and definition locations in `@std` source documents. Run
`ms stdlib <directory>` to materialize the exact pinned sources for editors that
require filesystem documents. These APIs provide navigation data; they do not
implement an LSP server or transport.
