+++
title = "Imports and exports"
weight = 1
+++

# Imports and exports

Each `.ms` file is a module with its own boundary. `export` makes a declaration available; `import` brings in one exported declaration. Resolved file paths identify modules. There is no `module` declaration, wildcard import, or cyclic dependency.

## Names and declaration order

Import several symbols with `import Name, OtherName from "./module.ms"`: a nonempty comma-separated list on one line. To wrap across lines, parenthesize the list (`import (Name, OtherName) from "./module.ms"`); a trailing comma is allowed there. `ms fmt` wraps a bare list wider than 88 columns into the parenthesized form, one name per line, and leaves parenthesized lists that fit on their line as written. Braces are rejected. Single-symbol `import Name from "./module.ms"` also works. Duplicate names and collisions are errors.

Types, interfaces, functions, and imports share one module namespace. Duplicates, import/declaration collisions, and overloads are rejected. Two modules that export the same name (for example `parse` in `@std/data/csv.ms` and `@std/data/toml.ms`) cannot both be imported into one module, and imports cannot be renamed. Import one, and wrap the other in a small module that exports it under a new name. Order does not matter: names and signatures are collected before bodies are checked, so forward references and mutual recursion work. Type layout cycles follow the [recursive data rule](../types/records.md#recursive-data).

The intrinsic core type names are `Bool`, `Int`, `Float`, `String`, `Unit`, and `Never`. The standard interfaces `Equal`, `Comparable`, `Hashable`, and `Clonable` also have fixed identities in the prelude. Declarations, imports, and type parameters cannot redefine these. Locals may reuse module-level names. They cannot shadow another local or parameter unless the new name starts with `_`; see [scope and shadowing](../basics/bindings.md#scope-and-shadowing). A value name cannot be used as a type.

Prelude declarations: `Optional`, `Result`, `Error`, `List`, `Map`, `Set`, `ListEntry`, `MapEntry`, the function `print`, and `none`, `ok`, `error`. A present optional is a plain value in a `T?` position; there is no `some(...)` constructor. Qualify a Result case when its types need context, for example `Result[Int, Error].ok(3)`. A module declaration or import reusing a prelude name is rejected ("reuses a prelude name"); locals, parameters, and type parameters may shadow them.

Explicit imports of any prelude declaration, including `Equal` and `Hashable`, are rejected with `MS2003`; remove the binding. Application declarations and imports cannot reuse prelude names. Other exports of those modules, such as collection builders, need explicit imports.

Other standard declarations (`Decimal`, `Bytes`, builders, `Closeable`, runtime and host APIs) are imported from `@std`; see the [API reference](../../standard-library/reference/_index.md).

Unqualified case shorthand applies only when lexical lookup finds no binding of that name. Candidates are cases of visible enum types (prelude, declared, or imported by name); exactly one must match, and an expected type cannot choose. `Type.Case` selects explicitly. Match patterns use the scrutinee type ([pattern matching](../control-flow/pattern-matching.md)).

Renaming, namespace imports, re-exports, and wildcards have no syntax. A dotted type path is not a namespace; import each type by name. Module-level statements and `var` are rejected. A module-level `let` declares a [constant](#constants).

## Constants

A module-level `let` names a value usable throughout the module; add `export` to share it. Save as `limits.ms` and run `ms run limits.ms`; it prints `100`, then `true`:

<!-- manuscript-example: {"mode":"run","stdout":"100\ntrue\n"} -->
```manuscript
export let MAX_ITEMS = 100
let NAMES: List[String] = ["Ada", "Grace"]
let LIMIT = MAX_ITEMS * 2

fn is_full(count: Int) Bool:
    return count >= LIMIT

export fn main() Int:
    print(MAX_ITEMS)
    print(is_full(200))
    return 0
```

The type comes from the annotation or initializer. The initializer is a constant expression: literals, constant interpolations, operators, list and map literals, payloadless cases (`none`, `State.Ready`), and other constants. Calls, constructors, functions, and `match` are not allowed. Self-dependent constants are rejected.

Group related constants with `let (`, one `name = value` entry per line, indented four spaces; the closing `)` aligns with `let`. Each entry is an independent constant, and `export let (` exports all of them. Save as `bounds.ms` and run `ms run bounds.ms`; it prints `1`, then `10`:

<!-- manuscript-example: {"mode":"run","stdout":"1\n10\n"} -->
```manuscript
let (
    LOW = 1
    HIGH: Int = LOW + 9
)

export fn main() Int:
    print(LOW)
    print(HIGH)
    return 0
```

A constant has no storage or initialization order; each use evaluates the initializer in place, so a list constant is always fresh. Locals and parameters shadow it. Constants cannot be assigned, and `main` must be a function.

## A visible contract

`src/domain/customers.ms` exports a nominal identifier type:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
export type CustomerId:
    value: String
```

`src/main.ms` imports it and constructs a value. Save both files at the shown paths, then run `ms run src/main.ms`; it prints `C-100`:

<!-- manuscript-example: {"mode":"run","build_files":{"domain/customers.ms":"export type CustomerId:\n    value: String"},"stdout":"C-100\n"} -->
```manuscript
import CustomerId from "./domain/customers.ms"

export fn main() Int:
    let customer = CustomerId("C-100")
    print(customer.value)
    return 0
```

Relative imports resolve from the importing file's directory. Paths include `.ms` and name a file exactly; there is no directory or extension lookup.

## Public signature closure

An exported function, data type, or contract cannot expose an internal nominal type through a parameter, result, field, case payload, generic bound, or operation signature, transitively. Save the negative example below as `private.ms`; `ms check private.ms` rejects it with `public signature exposes private type PrivateToken`. Imported exported types may appear without being re-exported. Generic parameters are not private declarations.

<!-- manuscript-example: {"mode":"reject","stderr_contains":"public signature exposes private type PrivateToken"} -->
```manuscript
type PrivateToken:
    value: String

// Rejected: callers cannot name the internal result type.
export fn issue() PrivateToken:
    return PrivateToken("token")
```

Exporting a record exposes every field and its constructor; an enum, every case and payload; an `interface`, every operation. `export opaque type` hides record fields and `export opaque enum` hides enum cases outside the declaring file; selective per-field visibility is unsupported ([public data surfaces](../types/records.md#public-data-surfaces)).

An `impl` in a source type's defining module is available wherever the type is used. An `impl` for an imported type stays local to the declaring module. Both follow the [coherence and visibility rules](../types/contracts.md#coherence-and-visibility).

## Standard-library imports

This import declaration selects `Queue`; a module containing only this declaration is valid and can be checked with `ms check imports.ms`:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import Queue from "@std/collections/queue.ms"
```

`@std` is always available, needs no `[aliases]` entry, and cannot be overridden. Importing one export does not import the other type names in its signature: importing `Queue` does not bring other names from the module into scope (`Result` is in the prelude). Host accessors are imported separately and return services when called.

## Optional aliases

A project-root `ms.toml` can define file and directory aliases. With `@domain` mapped to `./src/domain` and `@customers` to `./src/domain/customers.ms`, either program below selects the same type. Save one version as `main.ms` at the project root and run `ms run main.ms`; both print `C-100`:

<!-- manuscript-example: {"mode":"run","stdout":"C-100\n","build_files":{"src/domain/customers.ms":"export type CustomerId:\n    value: String","ms.toml":"[project]\nname = \"alias-example\"\nsource = \".\"\nentry = \"example.ms\"\n[aliases]\n\"@domain\" = \"./src/domain\"\n\"@customers\" = \"./src/domain/customers.ms\"\n"}} -->
```manuscript
import CustomerId from "@domain/customers.ms"

export fn main() Int:
    let customer = CustomerId("C-100")
    print(customer.value)
    return 0
```

<!-- manuscript-example: {"mode":"run","stdout":"C-100\n","build_files":{"src/domain/customers.ms":"export type CustomerId:\n    value: String","ms.toml":"[project]\nname = \"alias-example\"\nsource = \".\"\nentry = \"example.ms\"\n[aliases]\n\"@domain\" = \"./src/domain\"\n\"@customers\" = \"./src/domain/customers.ms\"\n"}} -->
```manuscript
import CustomerId from "@customers"

export fn main() Int:
    let customer = CustomerId("C-100")
    print(customer.value)
    return 0
```

Aliases change only how a path is written; module identity follows the resolved file.

Missing files, unknown aliases, missing exports, and cycles are compile errors. See [project configuration](../../developer-tooling/builds/project-configuration.md).

See [source structure](../basics/syntax.md) and [boundary contracts](boundaries.md).
