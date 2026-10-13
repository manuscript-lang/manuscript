# Type checker

Each non-blank input line is one program in a tiny expression language. For each line, print its type, or
the first error found with a 1-based column. A line that is empty or only spaces and tabs produces no
output. Input is ASCII; columns count characters from the start of the line (a tab is one column).

## Language

Types are `Int`, `Bool` and `Str`. Whitespace between tokens is spaces and tabs.

Tokens:

- integer literal: one or more ASCII digits (`007` is fine; the value never matters);
- string literal: `"` followed by any characters except `"` up to the next `"` (no escapes);
- identifier: a letter or `_`, then letters, digits or `_`. These words are keywords and are never
  identifiers: `let in if then else true false and or not`;
- operators and punctuation: `+ - * < <= > >= == != ( ) , =` (read greedily: `<=` is one token).

Any other character is a lexical error. Grammar (lowest precedence first):

    expr  := "let" ID "=" expr "in" expr
           | "if" expr "then" expr "else" expr
           | or
    or    := and ("or" and)*              (left associative)
    and   := not ("and" not)*             (left associative)
    not   := "not" not | cmp
    cmp   := add (CMPOP add)?             (CMPOP is < <= > >= == !=; at most one per level)
    add   := mul (("+" | "-") mul)*       (left associative)
    mul   := unary ("*" unary)*           (left associative)
    unary := "-" unary | atom
    atom  := INT | STR | "true" | "false" | ID | ID "(" [expr ("," expr)*] ")" | "(" expr ")"

`let` and `if` can only start an `expr`, so they may follow `let ... =`, `in`, `then`, `else`, `(`, `,`
or begin the line, but not appear as an operand (`1 + if ...` is a syntax error). `1 < 2 < 3` is a syntax
error because the second `<` cannot continue the expression. `ID "("` is always a call.

## Typing rules

Every expression node has a *start column*: the column of its first token. A parenthesised expression
starts at its `(` (so `(1 < 2) + 3` and the sum both start at the `(`). A binary node starts where its
left operand starts; a call starts at its function name; `-` and `not` start at their operator.

| construct | rule | result |
| --- | --- | --- |
| `INT`, `STR`, `true`/`false` | | `Int`, `Str`, `Bool` |
| variable | must be bound by an enclosing `let` | its type |
| `-e` | `e` is `Int` | `Int` |
| `not e` | `e` is `Bool` | `Bool` |
| `a + b` | `a` is `Int` or `Str`; `b` has the same type as `a` | that type |
| `a - b`, `a * b` | both `Int` | `Int` |
| `a < b`, `<=`, `>`, `>=` | both `Int` | `Bool` |
| `a == b`, `a != b` | `b` has the same type as `a` (any type) | `Bool` |
| `a and b`, `a or b` | both `Bool` | `Bool` |
| `if c then a else b` | `c` is `Bool`; `b` has the type of `a` | type of `a` |
| `let x = a in b` | `b` is checked with `x` bound to the type of `a` (shadowing allowed; `x` is not visible in `a`) | type of `b` |
| call | the function exists and is called with the right number of arguments, each of the right type | its result |

Built-in functions (the only functions; they live in a different namespace from variables, so a variable
never shadows one and a variable cannot be called):

    len(Str) -> Int      str(Int) -> Str      abs(Int) -> Int      even(Int) -> Bool
    min(Int, Int) -> Int   max(Int, Int) -> Int   concat(Str, Str) -> Str

## Order of checks and errors

The whole line is lexed first, then parsed, then type checked, so a lexical error anywhere beats a syntax
error, and a syntax error anywhere beats every type error. Within each phase the first error in the order
below wins, and only one error is printed.

Lexical errors (scanning left to right):

- `error: unexpected character 'C' at COL` for a character that starts no token (`COL` is its column);
- `error: unterminated string at COL` for a `"` with no closing `"` on the line (`COL` is the opening quote).

Syntax error: `error: syntax error at COL`, where `COL` is the column of the first token that the grammar
cannot accept. If the input ends too early, `COL` is one more than the length of the line with trailing
spaces and tabs removed.

Type checking visits nodes in this order, and the first failure is reported:

- Operands are checked before the operator that uses them, left to right. For a binary operator, both
  operands are fully checked (their own errors win) and only then are the operand types compared with the
  rule: left operand first, then right.
- `if`: check the condition and require `Bool` immediately; then check the `then` branch; then check the
  `else` branch; then compare the branch types.
- `let`: check the bound expression, then the body.
- Call: first the function name (unknown name gives `unknown function`), then the argument count, then the
  arguments in order, each checked and compared with its parameter type before the next is examined.

Messages (`COL` is the start column of the node named):

- `error: expected T, found U at COL`, where `T` is the required type, `U` the actual type and `COL` the
  start of the offending operand/branch/condition/argument. For `+`, when the left operand is neither
  `Int` nor `Str`, `T` is the text `Int or Str` and `COL` is the left operand; otherwise a wrong right
  operand reports the left operand's type as `T`. For `==`/`!=`, the right operand reports the left
  operand's type as `T`. For an `else` branch, `T` is the `then` branch type.
- `error: unbound variable NAME at COL` (the variable's column);
- `error: unknown function NAME at COL` (the function name's column);
- `error: wrong number of arguments for NAME: expected N, found M at COL` (the function name's column).

On success print `Int`, `Bool` or `Str`.

## Example

Input:

    1 + 2 * 3
    if 1 < 2 then "a" else "b"
    let x = 5 in x + true
    1 +

Output:

    Int
    Str
    error: expected Int, found Bool at 18
    error: syntax error at 4
