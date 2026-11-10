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

Comments start with `//` and run to the end of the line (a trailing comment follows code on its line). A multi-line comment is a `/* ... */` block on its own lines. The comment lines or block directly above a declaration, or a trailing `//` on its line, document it. See the [grammar](grammar.md) for the exact rules. Source is UTF-8 and case-sensitive. Identifiers use ASCII letters, digits, and underscores; text and comments may contain Unicode.

```manuscript
// A local binding can infer its type from the value.
let count = 3
```

## Terse style

Write the shortest form that stays clear; every form below already exists:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
fn check(rows: List[String], limit: Int) String:
    if rows.is_empty(): return "empty"
    if rows.any(fn r: r.length() > limit): return "too long"
    let blanks = rows.count(fn r: r.is_empty())
    let kind = if blanks == 0: "dense" else: "sparse"
    for i in 0..rows.length():
        if rows[i] == "stop": return "stopped at {i}"
    print("{kind} {blanks}")
    return kind
```

- `print(x)` writes a line, needs no import and never fails; reserve `stdout().write` for output whose failure you handle.
- A one-line `if c: return x` or `continue` replaces a two-line block.
- `xs[i]` reads in place; `for i in 0..n:` counts; `for x in xs:` when the index is unused.
- Prefer `any`, `all`, `count`, `sum`, `map`, `filter`, `fold` and `[0].repeated(n)` to a loop that builds or tests a collection.
- No `else` after a `return`; `for _i in 0..n:` when the counter is unused; `a.extend(b)` over an append loop; `(0..n)` is already a `List[Int]`; `x` and `not x` over `== true` and `== false`; `a.max(b)` over a compare-and-assign.
- `if let v = o:` or `o.get(d)` over `is_some()` then `get()`; `try` over `match` to unwrap a `Result`.
- `is_empty()` over `length() == 0`; `let x = if c: a else: b` over a `var` assigned in a branch; `m.get_or(k, d)` over `m.get(k).get(d)`.

## Module boundaries

A file's resolved path identifies its module. `export` makes a declaration visible to other modules:

```manuscript
import Customer from "./greeting.ms"
```

Relative imports resolve from the importing file's directory. `ms.toml` configures the source directory, entry file, and import aliases; see [modules and capabilities](../modules/_index.md) and [project configuration](../../developer-tooling/builds/project-configuration.md).

Next: [bindings](bindings.md), [types](../types/named-types.md), [function declarations](../functions/declarations-and-calls.md). Exact syntax is in the [grammar](grammar.md); precedence is in [expressions](expressions.md).
