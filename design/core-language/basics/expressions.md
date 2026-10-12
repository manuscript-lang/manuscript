+++
title = "Expressions and operators"
weight = 6
+++

# Expressions and operators

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

An expression produces a value, such as `count + 1`. A statement controls what runs or changes a binding. This page is the reference for operator precedence, allowed operand types, and evaluation order. Only the operators listed here are supported; Go operators are not automatically available.

## Precedence and grammar

Rows are ordered from highest to lowest precedence.

| Form | Associativity and restriction |
| --- | --- |
| Member access `.`, explicit type application `[...]`, call `(...)` | Left to right; type application is not runtime indexing |
| Prefix `+`, `-`, `try` | Right to left |
| `*`, `/`, `%` | Left to right |
| `+`, `-` | Left to right |
| `<`, `<=`, `>`, `>=`, `==`, `!=` | One comparison of either kind; cannot be chained or mixed without parentheses |
| `not` | Right to left; its operand includes comparisons |
| `and` | Left to right, short circuit |
| `or` | Left to right, short circuit |

```ebnf
Expression    = OrExpression ;
OrExpression  = AndExpression, { "or", AndExpression } ;
AndExpression = NotExpression, { "and", NotExpression } ;
NotExpression = "not", NotExpression | Comparison ;
Comparison    = Sum, [ ("<" | "<=" | ">" | ">=" | "==" | "!="), Sum ] ;
Sum           = Product, { ("+" | "-"), Product } ;
Product       = Prefix, { ("*" | "/" | "%"), Prefix } ;
Prefix        = ("+" | "-" | "try"), Prefix | Postfix ;
Postfix       = Primary, { ".", Name | TypeArguments | CallArguments } ;
CallArguments = "(", [ Argument, { ",", Argument }, [ "," ] ], ")" ;
Argument      = [ Name, ":" ], Expression ;
Primary       = IntLiteral | FloatLiteral | DecimalLiteral | StringLiteral
              | "true" | "false" | "unit" | "self" | Name
              | "(", Expression, ")" | SharedViewConstruction | ListLiteral | FunctionExpression ;
SharedViewConstruction = "(", SharedContractType, ")", CallArguments ;
ListLiteral   = "[", [ Expression, { ",", Expression }, [ "," ] ], "]" ;
FunctionExpression = "fn", "(", [ Parameters ], ")", "->", Type, Suite ;
```

The common `Comparison` production makes `a < b == c`, `a == b == c`, and `a < b < c` syntax errors. Comparisons with explicit grouping, such as `(a < b) == flag`, are ordinary Bool equality. `not a == b` means `not (a == b)`. `try read() + 1` means `(try read()) + 1`; use `try (expression)` to propagate the result of a larger expression.

A generic application in expression position, such as `identity[Int]` or `Box[String]`, supplies types to a resolved generic declaration. Its brackets cannot index a list. Collection/text lookup and updates use declared library operations; neither `values[0]` nor slicing syntax is supported. The grammar accepts member paths syntactically; resolution determines whether a member is a record field, alternative case, or operation. Argument labels are optional only for functions and methods with exactly one declared parameter; the checker enforces [call rules](../functions/declarations-and-calls.md#argument-names). Constructors and explicit contract views such as `Payments(value: card)` require labels.

A shared view uses `(Payments & Shareable)(value: card)`. The parenthesized type must be followed immediately by its named call; it is not a function value or a binary `&` expression. [Contract views](../types/contracts.md#shared-contract-views) define the required implementation and sharing proofs, generic context, and single `value` argument.

## Operand and result types

| Operator | Accepted operands | Result |
| --- | --- | --- |
| Unary `+`, `-` | Int, Float, or Decimal | Same numeric type |
| `+`, `-`, `*`, `/` | Both Int, both Float, or both Decimal | The common operand type |
| `%` | Both Int | Int |
| `<`, `<=`, `>`, `>=` | Both Int, both Float, or both Decimal | Bool |
| `==`, `!=` | Same exact type satisfying Equal | Bool |
| `not` | Bool | Bool |
| `and`, `or` | Both Bool | Bool |
| `try` | Result[T, E], with a compatible enclosing Result error type | T on success; propagates E on failure |
| `+`, `-` | Both Duration | Duration |
| `+`, `-` | Instant left, Duration right | Instant |
| `-` | Both Instant | Duration |
| `<`, `<=`, `>`, `>=` | Both Duration or both Instant in the same clock domain | Bool |

Decimal, Duration, Instant, and Result rows recognize their canonical standard declaration identities, even when operands are inferred; a local type with the same spelling does not enable these operators.

There is no mixed numeric arithmetic, numeric truthiness, text concatenation operator, or user-defined operator overload. For example, `1 + 0.5`, `"a" + "b"`, and `not 1` fail type checking. Use an explicit numeric conversion, text interpolation, or a library operation as appropriate. Equality and hashing eligibility follow [equality and hashing](../types/equality-and-hashing.md); exact compatibility and contextual inference follow [type rules](../types/compatibility.md).

Numeric exceptional values and rounding follow [numbers and booleans](numbers-and-booleans.md#runtime-numeric-outcomes). Duration/Instant ranges and clock-domain checks follow [time conversion](../../standard-library/data-and-io/operations.md#numeric-and-time-conversion). `Instant + Instant`, `Duration + Instant`, and unary Duration signs are rejected.

### Never operands

Choose an operator row from independently known operand types; the expected result type cannot choose it.

- For same-type numeric arithmetic, ordering, and equality, non-Never operands must establish one identical eligible type. Then accept Never at the remaining positions.
- For time arithmetic, the known operand positions must select exactly one table row.
- Two Never operands cannot choose a numeric, ordering, or equality row. Unary numeric signs and `try` also need an independently known numeric or Result operand.
- `not`, `and`, and `or` require Bool directly, so Never is permitted at their operand positions.

The result keeps the selected row's type even when evaluation cannot complete. `1 + panic(message: "stop")` has type Int; `1 == panic(message: "stop")` and `not panic(message: "stop")` have type Bool. `instant - panic(...)` is rejected because the right operand could be Duration or Instant. `let x: Int = -panic(message: "stop")` is rejected because the annotation cannot select its numeric operand type.

Ordinary [expected-type compatibility](../types/compatibility.md) still admits Never in calls and returns. [Error propagation](../errors/propagation.md) defines `try`'s function boundary and exact error-type requirement.

## Evaluation

Subexpressions evaluate from left to right. A binary operator evaluates its left operand once, then its right operand once, then applies the operator. The right side of `false and expression` and `true or expression` is not evaluated. Both branches must nevertheless type-check.

A call evaluates its callable or method receiver first and its supplied argument expressions once each in written order. Parameter declaration order does not reorder evaluation. Field access evaluates its receiver once. Explicit type arguments have no runtime evaluation. List elements evaluate in written order; an enclosing expected positional-pack contract can retain distinct per-position types, while ordinary [list literals](../types/collections.md) remain homogeneous.

A function expression creates a function value; its statement body runs on invocation, not creation. Its capture behavior is specified by [function values and closures](../functions/function-values-and-closures.md). String interpolation evaluates each embedded expression once in written order and then formats it, as specified by [text and bytes](text-and-bytes.md).

If evaluating a required subexpression exits through Result propagation or a fault, later subexpressions are not evaluated and the operation is not invoked. Lexical cleanup and cancellation behavior follow their separate contracts.

## Examples

```text
fn calculated(value: Int, active: Bool) -> Int:
    let product = 1 + 2 * 3             # 7
    let same = not value == product     # not (value == product)
    if active and same:
        return product
    return value
```

```text
fn invalid(value: Int, ratio: Float) -> Bool:
    let mixed = value + ratio           # Type error: exact numeric types differ.
    let indexed = [1, 2, 3][0]          # Syntax error: brackets take types here.
    return 0 < value < 10               # Syntax error: comparison chain.
```

Each rejected expression is independent; a parser need not type-check a function after a syntax error. Assignment `=`, compound assignment, bitwise operators, exponentiation, ranges, ternaries, tuples, and expression-valued blocks are not expression forms in this design.

[Previous: Source structure and syntax](syntax.md) · [Next: Bindings and scope](bindings.md)
