+++
title = "Expressions and operators"
weight = 5
+++

# Expressions and operators

An expression produces a value, such as `count + 1`. A statement controls what runs or changes a binding. This page is the reference for operator precedence, allowed operand types, and evaluation order. Only the operators listed here are supported.

## Precedence and grammar

Rows are ordered from highest to lowest precedence.

| Form | Associativity and restriction |
| --- | --- |
| Member access `.`, type application or list indexing `[...]`, call `(...)` | Left to right; brackets specialize declarations or index lists |
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
Postfix       = Primary, { ".", Name | TypeArguments | "[", Expression, "]" | CallArguments } ;
CallArguments = "(", [ Argument, { ",", Argument }, [ "," ] ], ")" ;
Argument      = [ Name, ":" ], Expression ;
Primary       = IntLiteral | FloatLiteral | DecimalLiteral | StringLiteral
              | "true" | "false" | "unit" | "self" | Name
              | "(", Expression, ")" | SharedViewConstruction | ListLiteral | MapLiteral | FunctionExpression | MatchExpression ;
SharedViewConstruction = "(", SharedContractType, ")", CallArguments ;
ListLiteral   = "[", [ Expression, { ",", Expression }, [ "," ] ], "]" ;
MapLiteral    = "{", [ MapEntry, { ",", MapEntry }, [ "," ] ], "}" ;
MapEntry      = Expression, ":", Expression ;
FunctionExpression = "fn", "(", [ CallbackParameters ], ")", [ "->", Type ], FunctionSuite ;
MatchExpression = "match", Expression, ":", NEWLINE, INDENT,
                  MatchArm, { MatchArm }, DEDENT ;
```

The common `Comparison` production makes `a < b == c`, `a == b == c`, and `a < b < c` syntax errors. Comparisons with explicit grouping, such as `(a < b) == flag`, are ordinary Bool equality. `not a == b` means `not (a == b)`. `try read() + 1` means `(try read()) + 1`; use `try (expression)` to propagate the result of a larger expression.

A generic application in expression position, such as `identity[Int]` or `Box[String]`, supplies types to a resolved generic declaration. When the receiver is a list value, brackets instead perform lookup: `values[index]` has the same `Optional[T]` result and negative-index behavior as `values.at(index)`. The receiver determines whether brackets supply types or an Int index; this does not depend on capitalization. Slicing and indexed assignment remain unsupported; use collection methods for updates. The grammar accepts member paths syntactically; resolution determines whether a member is a record field, alternative case, or operation. Calls may omit labels for single-parameter functions or use matching-name shorthand for multi-parameter functions; the checker enforces [call rules](../functions/declarations-and-calls.md#argument-names). Single-payload constructors and explicit contract views may omit their label, as in `Box(3)`, `some(3)`, or `Payments(card)`. Constructors with multiple payload fields require explicit labels.

Contract views use `Payments(card)` or `Payments(value: card)`. [Contract views](../types/contracts.md#explicit-contract-views) require an explicit implementation and exactly one `value` argument. There is no separate sharing refinement or shared constructor.

## Operand and result types

| Operator | Accepted operands | Result |
| --- | --- | --- |
| Unary `+`, `-` | Int, Float, or Decimal | Same numeric type |
| `+`, `-`, `*`, `/` | Both Int, both Float, or both Decimal | The common operand type |
| `+` | Both String | String |
| `%` | Both Int | Int |
| `<`, `<=`, `>`, `>=` | Both Int, both Float, both Decimal, or both String | Bool |
| `==`, `!=` | Same exact type satisfying Equal | Bool |
| `not` | Bool | Bool |
| `and`, `or` | Both Bool | Bool |
| `try` | Result[T, E], with a compatible enclosing Result error type | T on success; propagates E on failure |
| `+`, `-` | Both Duration | Duration |
| `+`, `-` | Instant left, Duration right | Instant |
| `-` | Both Instant | Duration |
| `<`, `<=`, `>`, `>=` | Both Duration or both Instant in the same clock domain | Bool |

Decimal, Duration, Instant, and Result rows recognize their canonical standard declaration identities, even when operands are inferred; a local type with the same spelling does not enable these operators.

String `+` concatenates two strings. String ordering is lexicographic by Unicode scalar value, with a shorter prefix first; it performs no normalization, case folding, or locale collation. Mixed numeric arithmetic, numeric truthiness, and user-defined operator overloads are unsupported. For example, `1 + 0.5`, `"a" + 1`, and `not 1` fail type checking. Use explicit conversion or interpolation when combining strings with other types. Equality and hashing eligibility follow [equality and hashing](../types/equality-and-hashing.md); exact compatibility and contextual inference follow [type rules](../types/compatibility.md).

Numeric exceptional values and rounding follow [numbers and booleans](numbers-and-booleans.md#runtime-numeric-outcomes). Duration/Instant ranges and clock-domain checks follow [time conversion](numbers-and-booleans.md#numeric-conversion). `Instant + Instant`, `Duration + Instant`, and unary Duration signs are rejected.

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

A call evaluates its callable or method receiver first and its supplied argument expressions once each in written order. Parameter declaration order does not reorder evaluation. Field access evaluates its receiver once. List indexing evaluates its receiver once, then its index once. Explicit type arguments have no runtime evaluation. List elements and map entries evaluate in written order; map keys precede their values. [Collection literals](../types/collections.md) retain homogeneous element, key, and value types.

A function expression creates a function value; its statement body runs on invocation, not creation. Its capture behavior is specified by [function values and closures](../functions/function-values-and-closures.md). String interpolation evaluates each embedded expression once in written order and then formats it, as specified by [text and bytes](text-and-bytes.md).

If evaluating a required subexpression exits through Result propagation or a fault, later subexpressions are not evaluated and the operation is not invoked. Lexical cleanup and cancellation behavior follow their separate contracts.

## Examples

```manuscript
fn calculated(value: Int, active: Bool) -> Int:
    let product = 1 + 2 * 3             # 7
    let same = not value == product     # not (value == product)
    if active and same:
        return product
    return value
```

```manuscript
fn invalid(value: Int, ratio: Float) -> Bool:
    let mixed = value + ratio           # Type error: exact numeric types differ.
    return 0 < value < 10               # Syntax error: comparison chain.
```

Each rejected expression is independent; a parser need not type-check a function after a syntax error. Assignment `=`, compound assignment, bitwise operators, exponentiation, ranges, ternaries, tuples, and expression-valued blocks are not expression forms in this design.
