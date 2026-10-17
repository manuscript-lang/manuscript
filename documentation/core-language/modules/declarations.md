+++
title = "Imports and exports"
weight = 1
+++

# Imports and exports

Each `.ms` file is a module: a group of declarations with its own boundary. Use `export` to make a declaration available to other files and `import` to bring an individual exported declaration into the current file. Resolved file paths identify modules. There is no `module` declaration, wildcard import, or cyclic module dependency.

## Names and declaration order

Import multiple symbols with `import { Name, OtherName } from "./module.ms"`.
The braces contain a nonempty, comma-separated list; a trailing comma and
multiple lines are permitted. Each name selects an export and enters the same
module namespace as a single-symbol import. Duplicate names and collisions are
errors. Single-symbol `import Name from "./module.ms"` remains supported.

Types, interfaces, module functions, and imported symbols share one ordinary module namespace. Duplicate names, import/declaration collisions, and function overloading are rejected. Imports and declarations may appear in any order: collect names and signatures before checking bodies, so forward references and mutually recursive functions work. Type layout cycles follow the separate [recursive data rule](../types/records.md#recursive-data), not module-cycle rules.

The intrinsic core type names are only `Bool`, `Int`, `Float`, `String`, `Unit`, and `Never`. They cover primitive literals, ordinary arithmetic, and function/control-flow typing. The source-backed standard interfaces `Equal` and `Hashable` also have fixed identities and are available through the prelude. A module declaration, import, or type parameter cannot redefine these names. They are resolved names rather than lexical keywords. Ordinary local bindings may shadow outer names, but a shadowed value name cannot be used as a type.

`Optional`, `Result`, `Error`, `List`, `Map`, `Set`, `CollectionError`, `ListEntry`, `MapEntry`, and `MissingValue` are source-backed standard declarations in the prelude. Their cases (`some`, `none`, `ok`, `error`, the `CollectionError` cases, and `MissingValue.Missing`) follow ordinary lookup and ambiguity rules; qualify `Result[T, E].error`, `CollectionError.OutOfRange`, or `MissingValue.Missing` when needed. A module declaration or application import with one of these type names selects that identity instead of the prelude type; import/declaration collisions still fail. Collection operations retain their canonical signature types even when an application declaration shadows a support type name.

Explicit imports that resolve to any canonical source-backed prelude declaration, including `Equal` and `Hashable`, are rejected with `MS2003`. Remove the named binding from a grouped import, or delete a singleton import. This rule checks declaration identity, so it permits application-owned types with the same names and imports through project aliases. Import renaming and re-exports remain unsupported. Other exports from these standard modules, such as collection factories and builders or `ErrorCategory`, require explicit imports.

Other standard declarations are explicit imports from the compiler-supplied `@std` directory, including `Decimal`, `Bytes`, collection builders, `Closeable`, and runtime/host APIs. See [standard imports](../../standard-library/imports.md) and the [API reference](../../standard-library/reference/_index.md) for their import paths. Compiler support follows the canonical standard declaration identity, never its spelling.

An unqualified case shorthand is considered only when ordinary lexical name lookup finds no binding or declaration of that name. The candidate cases come from visible alternative types from the prelude, declared in the module, or imported by name. Exactly one candidate is required; an expected type cannot choose among multiple candidates. `Type.Case` explicitly selects the nominal alternative. Match-pattern case lookup uses the scrutinee type, as specified by [pattern matching](../control-flow/pattern-matching.md).

Import renaming, namespace imports, re-exports, and wildcard imports have no syntax. A dotted type path does not create a module namespace; callers import each needed exported type by its own name. Qualified alternative constructors remain supported. Module-level executable statements and `var` bindings are rejected; local-value examples elsewhere are function-body fragments. A module-level `let` declares a [constant](#constants).

## Constants

A module-level `let` names a value that every function in the module can use. Add `export` to share it with other modules.

```manuscript
export let MAX_ITEMS = 100
let NAMES: List[String] = ["Ada", "Grace"]
let LIMIT = MAX_ITEMS * 2

fn is_full(count: Int) -> Bool:
    return count >= LIMIT
```

The type comes from the annotation or the initializer. The initializer is a constant expression: literals, text with constant interpolations, operators, list and map literals, payloadless cases such as `none` or `State.Ready`, and other constants. Calls, constructors, functions, and `match` belong in a function. A constant that depends on itself is rejected.

A constant has no storage and no initialization order. Each use evaluates the initializer, as if the value were written at that place, so a list constant always starts as a fresh list and changing a copy never affects the constant or another user. A local binding or parameter with the same name shadows the constant. Constants cannot be assigned, and `main` must be a function.

## A visible contract

The file `src/domain/customers.ms` exports a nominal identifier type:

```manuscript
export type CustomerId:
    value: String
```

The file `src/main.ms` imports the individual symbol:

```manuscript
import CustomerId from "./domain/customers.ms"
```

Exporting a type makes it part of the module boundary; an internal declaration stays within that boundary. A relative import resolves from the importing file's directory. Paths include the `.ms` extension and identify a file, with no implicit directory entry or extension lookup.

## Public signature closure

An exported function, data type, or contract cannot expose an internal nominal type through a parameter, result, field, case payload, generic bound, or operation signature. Check the transitive public type surface through nested applications and exposed data members. Exported types from other modules may appear in a public signature without automatically re-exporting their names. Generic parameters themselves are not private nominal declarations.

```manuscript
type PrivateToken:
    value: String

# Rejected: callers cannot name the internal result type.
export fn issue() -> PrivateToken:
    return PrivateToken("token")
```

Exporting a record exposes every field and its constructor; exporting an alternative exposes every case and payload field; exporting an `interface` exposes every operation. Opaque exports and selective member visibility are unsupported. See [public data surfaces](../types/records.md#public-data-surfaces).

An `impl` in a source type's defining module becomes available wherever that type is used. An `impl` for an imported source type is local to the declaring module and does not become visible through imports. The interface may be local or imported. Concrete and generic implementations follow the same [coherence and visibility rules](../types/contracts.md#coherence-and-visibility), including overlap rejection within the visible set and preservation of the selected implementation in explicit contract views.

## Standard-library imports

```manuscript
import TaskGroup from "@std/tasks.ms"
```

`@std` is always available without an `[aliases]` entry and cannot be overridden. Importing one export does not bring its signature's other type names into scope. For example, importing TaskGroup permits constructing a group and using inferred join results, but writing `ExecutionError` in an annotation requires its own import; `Result` is already in the prelude. Importing a contract supplies its interface. Separately imported host accessors return service values when called.

## Optional aliases

A project-root `ms.toml` can define file and directory aliases. With `@domain` mapped to `./src/domain` and `@customers` mapped to `./src/domain/customers.ms`, either import selects the same exported type:

```manuscript
import CustomerId from "@domain/customers.ms"
```

```manuscript
import CustomerId from "@customers"
```

Each example is an alternative import spelling for the same `CustomerId`. Aliases change how a path is written; module identity and visibility still follow the resolved file. Relative imports and aliases that resolve to the same file refer to the same module.

Missing files, unknown aliases, missing exports, and cyclic module dependencies are compile errors. The [project configuration](../../developer-tooling/builds/project-configuration.md) defines alias resolution and filesystem identity.

See [source structure](../basics/syntax.md) and [boundary contracts](boundaries.md).
