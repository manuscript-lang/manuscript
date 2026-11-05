+++
title = "Source files"
weight = 1
+++

# Source files

A `.ms` file is a module. Top level holds imports, types, functions, constants, and tests. Executable statements and local `let`/`var` bindings go inside a function or test. There is no `module` declaration or top-level initializer; a top-level `let` is a [constant](../modules/declarations.md#constants).

`src/greeting.ms`:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Welcome, Ada!\n"} -->
```manuscript
export type Customer:
    name: String
    active: Bool

export fn welcome(customer: Customer) String:
    if customer.active:
        return "Welcome, {customer.name}!"

    return "Your account is inactive."

export fn main() Int:
    print(welcome(Customer("Ada", true)))
    return 0
```

```text
Welcome, Ada!
```

## Blocks and layout

Indentation defines blocks: exactly four extra spaces per level. Tabs and semicolons are rejected. Blank and comment-only lines do not affect blocks.

Calls take positional arguments, optional labels, or both; an unlabeled argument is always positional. See [declarations and calls](../functions/declarations-and-calls.md).

Expressions inside parentheses, brackets, or braces can span lines:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Welcome, Ada!\n"} -->
```manuscript
type Customer:
    name: String
    active: Bool

fn welcome(customer: Customer) String:
    return "Welcome, {customer.name}!"

export fn main() Int:
    let customer = Customer(
        name: "Ada",
        active: true,
    )
    print(welcome(customer))
    return 0
```

```text
Welcome, Ada!
```

Comments start with `//` and run to the end of the line (a trailing comment follows code on its line). A multi-line comment is a `/* ... */` block on its own lines. The comment lines or block directly above a declaration, or a trailing `//` on its line, document it. See the [grammar](grammar.md) for the exact rules. Source is UTF-8 and case-sensitive. Identifiers use ASCII letters, digits, and underscores; text and comments may contain Unicode.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"3\n"} -->
```manuscript
export fn main() Int:
    // A local binding can infer its type from the value.
    let count = 3
    print(count)
    return 0
```

```text
3
```

## Module boundaries

A file's resolved path identifies its module. `export` makes a declaration visible to other modules:

Save the first complete program on this page as `greeting.ms`. Save the following caller as `example.ms` beside it, then run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Welcome, Ada!\n","build_files":{"greeting.ms":"export type Customer:\n    name: String\n    active: Bool\n\nexport fn welcome(customer: Customer) String:\n    if customer.active:\n        return \"Welcome, {customer.name}!\"\n\n    return \"Your account is inactive.\"\n\nexport fn main() Int:\n    print(welcome(Customer(\"Ada\", true)))\n    return 0\n"}} -->
```manuscript
import Customer, welcome from "./greeting.ms"

export fn main() Int:
    print(welcome(Customer("Ada", true)))
    return 0
```

```text
Welcome, Ada!
```

Relative imports resolve from the importing file's directory. `ms.toml` configures the source directory, entry file, and import aliases; see [modules and capabilities](../modules/_index.md) and [project configuration](../../developer-tooling/builds/project-configuration.md).

Next: [bindings](bindings.md), [records](../types/records.md), [function declarations](../functions/declarations-and-calls.md). Exact syntax is in the [grammar](grammar.md); precedence is in [expressions](expressions.md).
