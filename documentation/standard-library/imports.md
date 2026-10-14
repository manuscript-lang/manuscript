+++
title = "Standard imports"
weight = 1
+++

# Standard imports

Most standard names need an explicit import. An imported function or type follows the same scope rules as one declared in your own module.

```manuscript
import List from "@std/collections.ms"
import {filesystem, FileSystemError} from "@std/fs.ms"
```

Import a type outside the prelude when naming it in an annotation or constructor. A type inferred from a return value needs no separate import unless you name it in source. The [API reference](reference/_index.md) lists each module's declarations.

## Names and identity

`Bool`, `Int`, `Float`, `String`, `Unit`, `Never`, `Equal`, `Hashable`, `Optional`, `Result`, `Error`, `List`, `Map`, and `Set` are available without imports. The `some`, `none`, `ok`, and `error` cases are available through their prelude types. Every other standard name comes from an explicit `@std/…` import. Importing one name does not expose other names from that module; wildcard imports are unsupported.

`@std` is the reserved directory supplied by the compiler distribution. Standard identities are independent of its installation path. A module declaration or import can replace the prelude `Optional`, `Result`, `Error`, `List`, `Map`, or `Set` name. A local type called `Result` or `List` remains an ordinary application type; matching a standard spelling does not give it standard behavior. Imports still obey the usual collision and shadowing rules.

## Syntax that uses standard types

- Bracket list literals use the standard `List` from the prelude.
- A `d`-suffixed number needs `Decimal` from `@std/decimal.ms`.
- `try` recognizes the standard `Result` type.
- `with` uses the standard `Closeable` implementation or an interface declaring the exact `close() -> Unit` operation. Using an already-typed resource does not require an otherwise unused `Closeable` import.

Application code cannot add methods or implementations to intrinsic or standard-library types. Source types can implement standard interfaces according to the [implementation rules](../core-language/types/contracts.md#coherence-and-visibility).

## Types and service values

Importing `FileSystem` supplies a type. Calling the imported `filesystem()` function obtains the current execution's filesystem service. The same distinction applies to clocks, network access, and process services. Continue with [external services](services.md).
