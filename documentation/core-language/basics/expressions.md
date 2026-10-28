+++
title = "Expressions and operators"
weight = 5
+++

# Expressions and operators

Reference for operator precedence, operand types, and evaluation order. Only the operators listed here exist.

## Precedence and grammar

Rows are ordered from highest to lowest precedence.

| Form | Associativity and restriction |
| --- | --- |
| Member access `.`, type application or list indexing `[...]`, call `(...)` | Left to right; brackets specialize declarations or index lists |
| Prefix `+`, `-`, `try` | Right to left |
| `*`, `/`, `%` | Left to right |
| `+`, `-` | Left to right |
| Range `..` | Non-chainable; Int bounds, excludes the end; see [loops](../control-flow/loops.md) |
| `<`, `<=`, `>`, `>=`, `==`, `!=` | One comparison of either kind; cannot be chained or mixed without parentheses |
| `not` | Right to left; its operand includes comparisons |
| `and` | Left to right, short circuit |
| `or` | Left to right, short circuit |
| Conditional `a if c else b` | Right to left; below `or`, above the pipe |
| Pipe `\|` | Left to right; lowest precedence, see [pipe flows](#pipe-flows) |

```ebnf
Expression    = Pipe ;
Pipe          = Conditional, { "|", PipeStep } ;
Conditional   = OrExpression, [ "if", OrExpression, "else", Conditional ] ;
PipeStep      = [ "try" ], ( Name, { ".", Name }, [ CallArguments ] | Postfix-from-dot ) | "try" ;
OrExpression  = AndExpression, { "or", AndExpression } ;
AndExpression = NotExpression, { "and", NotExpression } ;
NotExpression = "not", NotExpression | Comparison ;
Comparison    = Range, [ ("<" | "<=" | ">" | ">=" | "==" | "!="), Range ] ;
Range         = Sum, [ "..", Sum ] ;
Sum           = Product, { ("+" | "-"), Product } ;
Product       = Prefix, { ("*" | "/" | "%"), Prefix } ;
Prefix        = ("+" | "-" | "try"), Prefix | Postfix ;
Postfix       = Primary, { ".", Name | TypeArguments | "[", Expression, "]" | CallArguments } ;
CallArguments = "(", [ Argument, { ",", Argument }, [ "," ] ], ")" ;
Argument      = [ Name, ":" ], Expression ;
Primary       = IntLiteral | FloatLiteral | DecimalLiteral | StringLiteral
              | "True" | "False" | "(", ")" | "self" | Name
              | "(", Expression, ")" | SharedViewConstruction | ListLiteral | MapLiteral | FunctionExpression | MatchExpression ;
SharedViewConstruction = "(", SharedContractType, ")", CallArguments ;
ListLiteral   = "[", [ Expression, { ",", Expression }, [ "," ] ], "]" ;
MapLiteral    = "{", [ MapEntry, { ",", MapEntry }, [ "," ] ], "}" ;
MapEntry      = Expression, ":", Expression ;
FunctionExpression = "lambda", [ CallbackParameters ], FunctionSuite
                   | "lambda", "(", [ CallbackParameters ], ")", [ "->", Type ], FunctionSuite ;
MatchExpression = "match", Expression, ":", NEWLINE, INDENT,
                  MatchArm, { MatchArm }, DEDENT ;
```

`Postfix-from-dot` in `PipeStep` is a chain starting with `.`, such as `.trim()` or `.items[0].name`.

- `a < b == c`, `a == b == c`, and `a < b < c` are syntax errors; `(a < b) == flag` is ordinary Bool equality.
- `not a == b` means `not (a == b)`.
- `try read() + 1` means `(try read()) + 1`; write `try (expression)` to propagate a larger expression.
- Brackets after a generic declaration supply types (`identity[Int]`, `Box[String]`); after a list value they look up: `values[index]` equals `values.get(index)`, a `T` accepting negative indexes that faults out of range. `values[index] = x` and `values[index] += x` are the `set` mutator (`values.set(index, x)`); the receiver must be a `var`. Slicing is unsupported.
- Calls take positional arguments and optional labels ([call rules](../functions/declarations-and-calls.md#argument-names)). Single-payload constructors may omit the label: `Box(3)`, `some(3)`. An interface is never constructed; see [interface conversion](../types/contracts.md#interface-conversion).

## Pipe flows

`lhs | step` passes `lhs` to the step. The parser rewrites each step into the ordinary call it names.

| Step | Means |
| --- | --- |
| `x \| f` | `f(x)` |
| `x \| f(a: 1)` | `f(x, a: 1)`: `x` becomes the first positional argument |
| `x \| m.f(2)` | `m.f(x, 2)` |
| `x \| .m(2)` | `x.m(2)`: a method, field, or index chain on the value |
| `x \| try step` | `try` of the step's result |
| `x \| try` | `try x`: unwrap the value so far |

```manuscript
fn load(path: String) Result[Config, ConfigError]:
    let config = try read(path)
        | try parse
        | normalize
        | try validate
    return ok(config)
```

- `|` has the lowest precedence: `a + b | f` is `f(a + b)`. Parenthesize a pipe used as an operand: `(x | f) == y`. A leading `try` binds only the head: `try read(path: path) | f`.
- A step is a name or member path, optionally with one argument list, or a `.` chain. Literals, function expressions, and calls inside the path are not steps; bind the function to a name first.
- `x | f(...)` always inserts `x` as the first positional argument; it cannot apply a function that `f(...)` returns.
- `try` before a step unwraps its result under the [propagation rules](../errors/propagation.md). Without `try`, a Result passes through unchanged. A flow may have several `try` steps.
- `.member`, call, or index directly after a step applies to its result: `x | f(a: 1).size()` is `f(x, a: 1).size()`. A `.member` on the next line is not part of the step: use `x | try .size()` to propagate `x.size()`.
- A line starting with `|` or `.` continues the statement; indent it exactly four spaces past the statement's first line.

## Operand and result types

| Operator | Accepted operands | Result |
| --- | --- | --- |
| Unary `+`, `-` | Any integer or float width, or Decimal | Same numeric type |
| `+`, `-`, `*`, `/` | Matching integer or float types, or both Decimal | The common operand type |
| `+` | Both String | String |
| `%` | Matching integer types | The common operand type |
| `..` | Both Int | List[Int]; a direct `for` uses a counter loop |
| `<`, `<=`, `>`, `>=` | Matching integer or float types, both Decimal, or both String | Bool |
| `==`, `!=` | Same exact type satisfying Equal | Bool |
| `not` | Bool | Bool |
| `and`, `or` | Both Bool | Bool |
| `try` | Result[T, E], with a compatible enclosing Result error type | T on success; propagates E on failure |
| `+`, `-` | Both Duration | Duration |
| `+`, `-` | Instant left, Duration right | Instant |
| `-` | Both Instant | Duration |
| `<`, `<=`, `>`, `>=` | Both Duration or both Instant in the same clock domain | Bool |

Decimal, Duration, Instant, and Result rows apply only to the standard declarations; a local type with the same name does not enable them.

- String ordering is lexicographic by Unicode scalar value, with no normalization, case folding, or collation.
- Mixed numeric arithmetic, numeric truthiness, and operator overloads do not exist: `1 + 0.5`, `"a" + 1`, and `not 1` fail checking. Convert or interpolate instead.
- `Instant + Instant`, `Duration + Instant`, and unary Duration signs are rejected.

See [equality and hashing](../types/equality-and-hashing.md), [type rules](../types/compatibility.md), and [numeric outcomes](numbers-and-booleans.md#runtime-numeric-outcomes).

### Never operands

The operand types, not the expected result type, select the operator row.

- Numeric arithmetic, ordering, and equality: the non-Never operands must fix one eligible type; Never fills the rest.
- Time arithmetic: known operands must select exactly one row.
- Two Never operands cannot select a numeric, ordering, or equality row; unary signs and `try` need an independently known operand.
- `not`, `and`, and `or` take Bool, so Never is fine.

The result keeps the row's type: `1 + panic(message: "stop")` is Int; `1 == panic(message: "stop")` is Bool. `instant - panic(...)` is rejected (Duration or Instant?), as is `let x: Int = -panic(message: "stop")`.

See [compatibility](../types/compatibility.md) and [error propagation](../errors/propagation.md) for Never in calls, returns, and `try`.

## Evaluation

- Subexpressions evaluate left to right, each once. The right side of `False and ...` and `True or ...` is skipped but must still type-check.
- A call evaluates its callable or receiver first, then arguments in written order (not parameter order).
- Indexing evaluates the receiver, then the index.
- List elements and map entries evaluate in written order, key before value ([collections](../types/collections.md)).
- A function expression only creates a value; its body runs on invocation ([closures](../functions/function-values-and-closures.md)).
- Interpolation evaluates embedded expressions once, in order ([text and bytes](text-and-bytes.md)).
- If a subexpression exits by Result propagation or fault, later subexpressions and the operation do not run.

## Examples

```manuscript
fn calculated(value: Int, active: Bool) Int:
    let product = 1 + 2 * 3             # 7
    let same = not value == product     # not (value == product)
    if active and same:
        return product
    return value
```

```manuscript
fn invalid(value: Int, ratio: Float) Bool:
    let mixed = value + ratio           # Type error: exact numeric types differ.
    return 0 < value < 10               # Syntax error: comparison chain.
```

Not expressions: assignment (a [statement](grammar.md#statements-and-patterns)), bitwise operators, exponentiation, tuples, and general expression-valued blocks. Conditional expressions use `a if condition else b`.
