+++
title = "Source files"
weight = 1
+++

# Source files

Each Manuscript source file ends in `.ms` and is a module. Put imports, type declarations, implementations, named functions, constants, and tests at the top level. Put executable statements and local `let` or `var` bindings inside a function or test. There is no separate `module` declaration or top-level initializer; a top-level `let` is a [constant](../modules/declarations.md#constants), not a statement.

The following `src/greeting.ms` file defines a customer and a function that creates a greeting. Read it from top to bottom:

```manuscript
export type Customer:
    name: String
    active: Bool

export fn welcome(customer: Customer) -> String:
    if customer.active:
        return "Welcome, {customer.name}!"

    return "Your account is inactive."
```

## Blocks and layout

Indentation defines blocks. Indented suites require exactly four additional spaces at each nesting level, and the formatter preserves that rule. Tabs in code and semicolons are rejected. Blank and comment-only lines do not change a block. The fields belong to `Customer` because they are indented under its declaration. The first return belongs to the `if` block; the second belongs directly to the function body.

Function and constructor calls accept positional arguments, optional labels, and mixtures of both. Matching-name shorthand remains available, such as `reduce(amount, deduction)`. See [declarations and calls](../functions/declarations-and-calls.md) for the call rules.

Expressions inside parentheses, brackets, or braces can span lines. This lets a call list its arguments on separate lines without changing their evaluation order:

```manuscript
let customer = Customer(
    name: "Ada",
    active: true,
)
```

Comments outside text literals begin with `#` and continue through the physical line. Identifiers use ASCII letters, digits, and underscores; text and comments may contain Unicode. Source is UTF-8, and names are case-sensitive.

```manuscript
# A local binding can infer its type from the value.
let count = 3
```

## Module boundaries

The resolved path of `src/greeting.ms` identifies its module. `export` makes a declaration available outside that module. Another file in `src` can import its customer type with:

```manuscript
import Customer from "./greeting.ms"
```

Relative imports resolve from the importing file's directory. A project-root `ms.toml` configures the source directory, entry file, and optional import aliases. The rules for imports, visibility, and dependency cycles are in [modules and capabilities](../modules/_index.md); see [project configuration](../../developer-tooling/builds/project-configuration.md) for path resolution.

The [normative grammar](grammar.md) defines accepted tokens, declarations, indentation, and anonymous-function suites. [Expressions and operators](expressions.md) defines precedence, operand types, and evaluation order. The local binding examples above are function-body fragments.

Continue with [bindings](bindings.md), [records](../types/records.md), and [function declarations](../functions/declarations-and-calls.md) to understand each declaration in the example.

See the [grammar reference](grammar.md) for exact syntax.
