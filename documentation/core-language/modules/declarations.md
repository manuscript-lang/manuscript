+++
title = "Imports and exports"
weight = 1
+++

# Imports and exports

Each `.ms` file is a module with its own boundary. `export` makes a declaration available; `import` brings in one exported declaration. Resolved file paths identify modules. There is no `module` declaration, wildcard import, or cyclic dependency.

## Names and declaration order

Import several symbols with `import { Name, OtherName } from "./module.ms"`: a nonempty comma-separated list, trailing comma and multiple lines allowed. Single-symbol `import Name from "./module.ms"` also works. Duplicate names and collisions are errors.

Types, interfaces, functions, and imports share one module namespace. Duplicates, import/declaration collisions, and overloads are rejected. Order does not matter: names and signatures are collected before bodies are checked, so forward references and mutual recursion work. Type layout cycles follow the [recursive data rule](../types/records.md#recursive-data).

The intrinsic core type names are `Bool`, `Int`, `Float`, `String`, `Unit`, and `Never`. The standard interfaces `Equal` and `Hashable` also have fixed identities in the prelude. Declarations, imports, and type parameters cannot redefine these. Locals may shadow outer names, but a shadowed value name cannot be used as a type.

Prelude declarations: `Optional`, `Result`, `Error`, `List`, `Map`, `Set`, `CollectionError`, `ListEntry`, `MapEntry`, `MissingValue`, and the constructors `some`, `none`, `ok`, `error`. Qualify cases when needed (`Result[T, E].error`, `CollectionError.OutOfRange`). A module declaration or import reusing a prelude name is rejected ("reuses a prelude name"); locals, parameters, and type parameters may shadow them.

Explicit imports of any prelude declaration, including `Equal` and `Hashable`, are rejected with `MS2003`; remove the binding. The rule checks declaration identity, so application types with those names and imports via project aliases are fine. Other exports of those modules, such as collection builders or `ErrorCategory`, need explicit imports.

Other standard declarations (`Decimal`, `Bytes`, builders, `Closeable`, runtime and host APIs) are imported from `@std`; see the [API reference](../../standard-library/reference/_index.md).

Unqualified case shorthand applies only when lexical lookup finds no binding of that name. Candidates are cases of visible alternative types (prelude, declared, or imported by name); exactly one must match, and an expected type cannot choose. `Type.Case` selects explicitly. Match patterns use the scrutinee type ([pattern matching](../control-flow/pattern-matching.md)).

Renaming, namespace imports, re-exports, and wildcards have no syntax. A dotted type path is not a namespace; import each type by name. Module-level statements and `var` are rejected. A module-level `let` declares a [constant](#constants).

## Constants

A module-level `let` names a value usable throughout the module; add `export` to share it.

```manuscript
export let MAX_ITEMS = 100
let NAMES: List[String] = ["Ada", "Grace"]
let LIMIT = MAX_ITEMS * 2

fn is_full(count: Int) -> Bool:
    return count >= LIMIT
```

The type comes from the annotation or initializer. The initializer is a constant expression: literals, constant interpolations, operators, list and map literals, payloadless cases (`none`, `State.Ready`), and other constants. Calls, constructors, functions, and `match` are not allowed. Self-dependent constants are rejected.

A constant has no storage or initialization order; each use evaluates the initializer in place, so a list constant is always fresh. Locals and parameters shadow it. Constants cannot be assigned, and `main` must be a function.

## A visible contract

`src/domain/customers.ms` exports a nominal identifier type:

```manuscript
export type CustomerId:
    value: String
```

`src/main.ms` imports it:

```manuscript
import CustomerId from "./domain/customers.ms"
```

Relative imports resolve from the importing file's directory. Paths include `.ms` and name a file exactly; there is no directory or extension lookup.

## Public signature closure

An exported function, data type, or contract cannot expose an internal nominal type through a parameter, result, field, case payload, generic bound, or operation signature, transitively. Imported exported types may appear without being re-exported. Generic parameters are not private declarations.

```manuscript
type PrivateToken:
    value: String

# Rejected: callers cannot name the internal result type.
export fn issue() -> PrivateToken:
    return PrivateToken("token")
```

Exporting a record exposes every field and its constructor; an alternative, every case and payload; an `interface`, every operation. Opaque exports and selective visibility are unsupported ([public data surfaces](../types/records.md#public-data-surfaces)).

An `impl` in a source type's defining module is available wherever the type is used. An `impl` for an imported type stays local to the declaring module. Both follow the [coherence and visibility rules](../types/contracts.md#coherence-and-visibility).

## Standard-library imports

```manuscript
import TaskGroup from "@std/tasks.ms"
```

`@std` is always available, needs no `[aliases]` entry, and cannot be overridden. Importing one export does not import the other type names in its signature: importing TaskGroup does not bring `ExecutionError` into scope (`Result` is in the prelude). Host accessors are imported separately and return services when called.

## Optional aliases

A project-root `ms.toml` can define file and directory aliases. With `@domain` mapped to `./src/domain` and `@customers` to `./src/domain/customers.ms`, either import selects the same type:

```manuscript
import CustomerId from "@domain/customers.ms"
```

```manuscript
import CustomerId from "@customers"
```

Aliases change only how a path is written; module identity follows the resolved file.

Missing files, unknown aliases, missing exports, and cycles are compile errors. See [project configuration](../../developer-tooling/builds/project-configuration.md).

See [source structure](../basics/syntax.md) and [boundary contracts](boundaries.md).
