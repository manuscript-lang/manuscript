+++
title = "Modules, exports, and imports"
weight = 77
+++

# Modules, exports, and imports

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Each `.ms` file is a module: a group of declarations with its own boundary. Use `export` to make a declaration available to other files and `import` to bring an individual exported declaration into the current file. Resolved file paths identify modules. There is no `module` declaration, wildcard import, or cyclic module dependency.

## Names and declaration order

Types, interfaces, module functions, and imported symbols share one ordinary module namespace. Duplicate names, import/declaration collisions, and function overloading are rejected. Imports and declarations may appear in any order: collect names and signatures before checking bodies, so forward references and mutually recursive functions work. Type layout cycles follow the separate [recursive data rule](../../core-language/types/records.md#recursive-data), not module-cycle rules.

The intrinsic core type names are only `Bool`, `Int`, `Float`, `String`, `Unit`, and `Never`. They cover primitive literals, ordinary arithmetic, and function/control-flow typing. The compiler bounds `Shareable`, `Equal`, and `Hashable` also have fixed identities. A module declaration, import, or type parameter cannot redefine these names. They are resolved names rather than lexical keywords. Ordinary local bindings may shadow outer names, but a shadowed value name cannot be used as a type.

All other standard declarations are explicit imports from the compiler-supplied `@std` directory, including `Decimal`, `Bytes`, collections, `Optional`, `Result`, `Closeable`, and runtime/host APIs. The [standard imports and API typing](../../standard-library/types/prelude.md) page lists their modules. These names are ordinary exports: without an import, a module may declare its own `Result`, `List`, or `parallel`. Import/declaration collisions still fail. Compiler support follows the canonical standard declaration identity, never its spelling. Optional/Result case shorthand becomes visible when its alternative type is imported and follows ordinary lookup and ambiguity rules; qualify `Result[T, E].error` when a local spelling shadows it.

An unqualified case shorthand is considered only when ordinary lexical name lookup finds no binding or declaration of that name. The candidate cases come from visible alternative types declared in the module or imported by name. Exactly one candidate is required; an expected type cannot choose among multiple candidates. `Type.Case` explicitly selects the nominal alternative. Match-pattern case lookup uses the scrutinee type, as specified by [pattern matching](../../core-language/control-flow/pattern-matching.md).

Import renaming, namespace imports, re-exports, and wildcard imports have no syntax. A dotted type path does not create a module namespace; callers import each needed exported type by its own name. Qualified alternative constructors remain supported. Module-level executable statements and bindings are rejected; local-value examples elsewhere are function-body fragments.

## A visible contract

The file `src/domain/customers.ms` exports a nominal identifier type:

```text
export type CustomerId:
    value: String
```

The file `src/main.ms` imports the individual symbol:

```text
import CustomerId from "./domain/customers.ms"
```

Exporting a type makes it part of the module boundary; an internal declaration stays within that boundary. A relative import resolves from the importing file's directory. Paths include the `.ms` extension and identify a file, with no implicit directory entry or extension lookup.

## Public signature closure

An exported function, data type, or contract cannot expose an internal nominal type through a parameter, result, field, case payload, generic bound, or operation signature. Check the transitive public type surface through nested applications and exposed data members. Exported types from other modules may appear in a public signature without automatically re-exporting their names. Generic parameters themselves are not private nominal declarations.

```text
type PrivateToken:
    value: String

# Rejected: callers cannot name the internal result type.
export fn issue() -> PrivateToken:
    return PrivateToken(value: "token")
```

Exporting a record exposes every field and its constructor; exporting an alternative exposes every case and payload field; exporting an `interface` exposes every operation. Opaque exports and selective member visibility are unsupported. See [public data surfaces](../../core-language/types/records.md#public-data-surfaces).

An `impl` belongs to the receiver's nominal data type's defining module and becomes available when that module is loaded. Imported public contracts can be implemented there. Concrete and generic implementations do not re-export declarations. Duplicate or overlapping receiver/instantiated contract pairs are rejected, ignoring bounds when checking overlap; bounds cannot choose competing implementations. These [coherence rules](../../core-language/types/contracts.md#coherence-and-visibility) prevent behavior from depending on unrelated imports.

## Standard-library imports

```text
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import map_error from "@std/result.ms"
import parallel from "@std/tasks.ms"
```

`@std` is always available without an `[aliases]` entry and cannot be overridden. Importing one export does not bring its signature's other type names into scope. For example, importing `parallel` permits matching its inferred result, but writing `Result` or `ExecutionError` in an annotation requires their own imports. Importing a contract supplies its interface, not an authority-bearing value.

## Optional aliases

A project-root `ms.toml` can define file and directory aliases. With `@domain` mapped to `./src/domain` and `@customers` mapped to `./src/domain/customers.ms`, either import selects the same exported type:

```text
import CustomerId from "@domain/customers.ms"
```

```text
import CustomerId from "@customers"
```

Each example is an alternative import spelling for the same `CustomerId`. Aliases change how a path is written; module identity and visibility still follow the resolved file. Relative imports and aliases that resolve to the same file refer to the same module.

Missing files, unknown aliases, missing exports, and cyclic module dependencies are compile errors. The [project configuration](../../compiler/builds/project-configuration.md) defines alias resolution and filesystem identity.

See [source structure](../../core-language/basics/syntax.md) and [boundary contracts](boundaries.md).

[Next: Boundary contracts](../modules/boundaries.md)
