+++
title = "Source files"
weight = 1
+++

# Source files

A `.ms` file is a module. Top level holds imports, types, functions, constants, and tests. Executable statements and local `let`/`var` bindings go inside a function or test. There is no `module` declaration or top-level initializer; a top-level `let` is a [constant](../modules/declarations.md#constants).

`src/greeting.ms`:

```manuscript
export type Customer:
    name: String
    active: Bool

export fn welcome(customer: Customer) String:
    if customer.active:
        return "Welcome, {customer.name}!"

    return "Your account is inactive."
```

## Blocks and layout

Indentation defines blocks: exactly four extra spaces per level. Tabs and semicolons are rejected. Blank and comment-only lines do not affect blocks.

Calls take positional arguments, optional labels, or both; an unlabeled argument is always positional. See [declarations and calls](../functions/declarations-and-calls.md).

Expressions inside parentheses, brackets, or braces can span lines:

```manuscript
let customer = Customer(
    name: "Ada",
    active: true,
)
```

Comments start with `#` and run to the end of the line. Source is UTF-8 and case-sensitive. Identifiers use ASCII letters, digits, and underscores; text and comments may contain Unicode.

```manuscript
# A local binding can infer its type from the value.
let count = 3
```

## Module boundaries

A file's resolved path identifies its module. `export` makes a declaration visible to other modules:

```manuscript
import Customer from "./greeting.ms"
```

Relative imports resolve from the importing file's directory. `ms.toml` configures the source directory, entry file, and import aliases; see [modules and capabilities](../modules/_index.md) and [project configuration](../../developer-tooling/builds/project-configuration.md).

Next: [bindings](bindings.md), [records](../types/records.md), [function declarations](../functions/declarations-and-calls.md). Exact syntax is in the [grammar](grammar.md); precedence is in [expressions](expressions.md).
