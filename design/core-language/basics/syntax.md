+++
title = "Source structure and syntax"
weight = 4
+++

# Source structure and syntax

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A Manuscript source file has the `.ms` extension and is itself a module. It contains imports, types, implementations, named functions, and tests, without an explicit `module` declaration. Executable statements and `let`/`var` bindings belong inside function or test bodies; there is no module initializer. Read the following `src/greeting.ms` example from top to bottom: it defines a customer, then a function that produces a greeting.

```text
export type Customer:
    name: String
    active: Bool

export fn welcome(customer: Customer) -> String:
    if customer.active:
        return "Welcome, {customer.name}!"

    return "Your account is inactive."
```

## Blocks and layout

Indentation defines blocks. Source suites require exactly four additional spaces at each nesting level, and the formatter preserves that rule. Tabs in code and semicolons are rejected. Blank and comment-only lines do not change a block. The fields belong to `Customer` because they are indented under its declaration. The first return belongs to the `if` block; the second belongs directly to the function body.

Every supplied function argument is named, including a single argument. Constructors also name their fields. See [declarations and calls](../functions/declarations-and-calls.md) for the call rules.

Expressions inside parentheses, brackets, or braces can span lines. This lets a call list its arguments on separate lines without changing their evaluation order:

```text
let customer = Customer(
    name: "Ada",
    active: true,
)
```

Comments outside text literals begin with `#` and continue through the physical line. Identifiers use ASCII letters, digits, and underscores; text and comments may contain Unicode. Source is UTF-8, and names are case-sensitive.

```text
# A local binding can infer its type from the value.
let count = 3
```

## Module boundaries

The resolved path of `src/greeting.ms` identifies its module. `export` makes a declaration available outside that module. Another file in `src` can import its customer type with:

```text
import Customer from "./greeting.ms"
```

Relative imports resolve from the importing file's directory. A project-root `ms.toml` configures the source directory, entry file, and optional import aliases. The rules for imports, visibility, and dependency cycles are in [modules and capabilities](../../modules-and-capabilities/modules/_index.md); see [project configuration](../../compiler/builds/project-configuration.md) for path resolution.

The [normative grammar](grammar.md) defines accepted tokens, declarations, indentation, and anonymous-function suites. [Expressions and operators](expressions.md) defines precedence, operand types, and evaluation order. The local binding examples above are function-body fragments.

Continue with [bindings](bindings.md), [records](../types/records.md), and [function declarations](../functions/declarations-and-calls.md) to understand each declaration in the example.

[Next: Source grammar](grammar.md)
