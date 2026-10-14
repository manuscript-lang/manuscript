# Lisp interpreter

Write an interpreter for a small Scheme-like language. The whole of standard input is one program: a
sequence of top-level forms. The interpreter reads the first form, evaluates it, then reads the next form,
and so on. Anything the program prints goes to standard output. The values of top-level forms are **not**
echoed. The exit status is always 0, including after an error (errors are reported on standard output, see
*Errors*).

Input is ASCII. A string is a sequence of bytes; there is no character type.

## Data

| type | notes |
| --- | --- |
| integer | signed 64-bit; any result outside `-9223372036854775808 .. 9223372036854775807` is the error `integer overflow` |
| boolean | `#t`, `#f` |
| string | immutable |
| symbol | case sensitive |
| pair, empty list `()` | lists are chains of pairs ending in `()`; pairs are mutable (`set-car!`, `set-cdr!`) |
| procedure | user lambdas and builtins |
| void | the "unspecified" value returned by `define`, `set!`, `display`, `if` without else, etc. |

Only `#f` is false. Everything else (including `0`, `""`, `()`) is true.

## Reader

- Whitespace: space, tab, newline, carriage return. A `;` starts a comment that runs to the end of the line.
- `(` `)` delimit lists. `'x` reads as `(quote x)` (and `'` may precede any datum, including another `'`).
- Dotted pairs: `(a b . c)`. The `.` must be a token by itself (followed by whitespace, a parenthesis, a `"`,
  a `;` or the end of input) and must be preceded by at least one element and followed by exactly one datum then `)`.
- Strings: `"..."` with escapes `\n`, `\t`, `\\`, `\"`. Strings may contain raw newlines.
- Atoms end at whitespace, `(`, `)`, `"` or `;`. An atom is, in this order:
  `#t` or `#f` (booleans); an integer if it matches `-?[0-9]+` (so `+5` is a symbol; a literal outside the
  int64 range is a reader error); otherwise a symbol. An atom starting with `#` that is not `#t`/`#f` is a
  reader error. A lone `.` outside the dotted position is a reader error. `'` inside an atom is an ordinary
  character (`a'b` is one symbol).

Reader errors (each aborts the program, see *Errors*), exact messages:

| situation | message |
| --- | --- |
| `)` with no open list | `syntax error: unexpected )` |
| input ends inside a list, after `'`, or after a dotted tail | `syntax error: unexpected end of input` |
| input ends inside a string | `syntax error: unterminated string` |
| unknown string escape | `syntax error: bad escape` |
| `#...` atom other than `#t`/`#f` | `syntax error: bad token: ` followed by the atom (e.g. `syntax error: bad token: #x`) |
| integer literal out of range | `syntax error: integer out of range` |
| a lone `.` read as a datum (top level, after `'`, or as the datum after the dot) | `syntax error: unexpected .` |
| `.` first in a list, or more than one datum after it | `syntax error: bad dotted list` |

Reader errors happen when that form is reached: output produced by earlier forms is kept.

## Evaluation

- Integers, strings, booleans evaluate to themselves. A symbol evaluates to its binding (innermost frame outward);
  an unbound one is `unbound variable: NAME`.
- `()` evaluated is the error `syntax error: empty application`. A list that is not proper, e.g. `(f . 1)`, is
  `syntax error: bad application`.
- Otherwise a list whose first element is a symbol naming a special form (below) is that special form, **even if a
  variable with that name has been defined**. Any other list is an application: evaluate the operator, then the
  operands **left to right**, then apply. If the operator is not a procedure: `not a procedure: ` + written form
  of the value.
- Environments are chains of frames. The global frame holds all builtins as ordinary variables (so
  `(define car cdr)` is allowed). Every lambda call and every `let`/`let*`/`letrec`/named-let creates a new
  frame. `define` binds (or rebinds) in the **innermost** frame. `set!` updates the nearest frame that has the
  name.

### Special forms

Syntax is checked when the form is evaluated, not when it is read or when a lambda containing it is created.
A form whose shape does not match is the error `syntax error: bad form: NAME` where NAME is the form keyword
(`if`, `define`, ...). Shapes (`body` means one or more expressions; the value of a body is its last expression):

- `(quote datum)`
- `(if test then)` and `(if test then else)`; a false test without else gives void
- `(define name expr)`; `(define (name param...) body)`; `(define (name param... . rest) body)`.
  Result is void. If the value expression is literally a `(lambda ...)` form the resulting procedure is named
  `name` (this affects only printing and error messages); `(define (f ...) ...)` also names it `f`.
- `(set! name expr)` (error `unbound variable: NAME` if never defined); result void
- `(lambda params body)` where params is `(a b)`, `(a b . rest)` or a single symbol `args` (all arguments as a list).
  A parameter list with a non-symbol or a repeated name is bad form.
- `(begin expr...)`; `(begin)` is void
- `(let ((name init)...) body)`: inits are evaluated in the outer environment, then a new frame binds all names.
  `(let name ((var init)...) body)` is named let: inits evaluated in the outer environment, `name` is bound to the
  loop procedure (named `name`) in an enclosing frame, and the body runs as a call of it. `(let () body)` is fine.
- `(let* ((name init)...) body)`: one new frame; each init is evaluated in that frame in order and its name is bound
  immediately after (later inits see earlier names; a name appearing twice is rebound).
- `(letrec ((name init)...) body)`: same evaluation as `let*` (this implementation level treats them identically).
- `(cond clause...)`: a clause is a non-empty list. `(else body)` is only allowed as the last clause and needs a body.
  `(test body...)` evaluates the body when the test is true and gives its last value; `(test)` alone gives the test
  value when it is true. No clause matching gives void. Clauses after the first match are not examined (and not
  checked for shape). `=>` has no special meaning (it is just a symbol).
- `(and expr...)`, `(or expr...)`: short circuit; `(and)` is `#t`, `(or)` is `#f`; `and` returns the first false
  value or the last value; `or` returns the first true value or `#f`.
- `(when test body)`, `(unless test body)`: void when the condition does not fire.
- `(try expr handler)`: evaluates `expr`; if it raises a runtime error (anything in the *Errors* table except
  `syntax error:` ones), calls `handler` (an expression evaluated after the failure, in the same environment) with
  the error message as a string and returns its result. A syntax error is never caught. Side effects done before
  the failure remain.

### Tail calls and the recursion limit

Calls in tail position must not grow any stack: the last expression of a lambda/`let`/`let*`/`letrec`/named-let
body, the chosen branch of `if`, the last expression of `begin`, `when`, `unless`, `cond` clause bodies,
and the last operand of `and`/`or`. Programs loop 100000+ times this way.

The *call depth* is the number of procedure bodies currently running that were entered from a non-tail position
(a tail call replaces the running frame instead of adding one). Builtins that call procedures (`map`, `for-each`,
`filter`, `fold`, `foldr`, `apply`, `sort`, the `try` handler) call them as non-tail. Entering a call that would make
the depth exceed **10000** is the error `recursion limit exceeded`. Tests only use depths clearly below the limit
(at most about 9000) or runaway recursion.

## Output and printing

`display` prints strings raw (also nested inside lists), `write` prints strings quoted with escapes `\\` `\"` `\n` `\t`.
Both print other values the same way: integers in decimal; `#t`/`#f`; symbols as written; lists as `(1 2 3)`;
improper as `(1 2 . 3)`; empty `()`; void as `#<void>`; a user procedure `#<procedure NAME>` (or `#<procedure>`
when anonymous); a builtin `#<builtin NAME>`. Programs never print cyclic structures. `newline` prints `\n`.

## Builtins

Arity is `n`, `a..b`, or `n+` (n or more). A wrong argument count is
`wrong number of arguments to NAME: expected E, got N` where E is `n`, `a to b`, or `at least n`, and NAME is the
procedure's name (`lambda` for an anonymous user procedure). A wrong argument type is
`NAME: expected KIND, got VALUE` with KIND one of `integer`, `string`, `list`, `pair`, `symbol`, `procedure` and
VALUE in `write` form (e.g. `+: expected integer, got "a"`). Argument types are checked left to right; an
argument count error comes before type errors. "list" means a proper list.

Numbers: `+`(0+) `-`(1+; one argument negates) `*`(0+) `quotient`(2) `remainder`(2) `modulo`(2) `abs`(1) `min`(1+)
`max`(1+) `=` `<` `>` `<=` `>=` (2+, chained: `(< 1 2 3)`; all arguments are type-checked first).
`quotient` truncates toward zero, `remainder` has the sign of the dividend, `modulo` the sign of the divisor.
Division by zero (any of the three): `division by zero`. `zero?` `even?` `odd?` (1).

Predicates and equality: `not`(1) `null?` `pair?` `list?` `number?` `string?` `symbol?` `boolean?` `procedure?` (1).
`eq?`(2): true only for the same integer, the same boolean, the same symbol, or two empty lists; always false for
strings, pairs, procedures. `equal?`(2): structural for pairs, equal strings/integers/booleans/symbols, empty
lists; procedures only equal if the same procedure.

Pairs and lists: `cons`(2) `car`(1) `cdr`(1) `cadr` `cddr` `caddr` (1; type error is `NAME: expected pair, got V`
for the value that is not a pair at the failing step) `set-car!`(2) `set-cdr!`(2) `list`(0+) `length`(1)
`append`(0+; all but the last argument must be lists; the last may be anything) `reverse`(1)
`list-ref`(2) `list-tail`(2) (index outside range: `list-ref: index out of range`; for `list-tail` indexes
`0..length` are valid) `range`(2) (`(range 3 6)` is `(3 4 5)`, empty if a >= b) `assoc`(2) `member`(2)
(both use `equal?`; `assoc` returns the pair or `#f`, every element of the alist must be a pair; `member` returns
the tail or `#f`).

Higher-order: `map`(2+: one or more lists, stops at the shortest) `for-each`(2+, void) `filter`(2)
`fold`(3: `(fold f init lst)` calls `(f acc elem)`, left to right) `foldr`(3: calls `(f elem acc)`, right to left)
`apply`(2+: `(apply f a b '(c d))`, last argument is a list) `sort`(2: `(sort lst less?)`, stable merge sort;
`less?` is called as `(less? later earlier)` and the later element goes first only when it returns true).
The procedure argument is checked as `procedure` before the lists.

Strings: `string-length`(1) `string-append`(0+) `substring`(3: `0 <= start <= end <= length`, else
`substring: index out of range`) `string-ref`(2: returns a 1-character string; `string-ref: index out of range`)
`string=?`(2) `string<?`(2, byte order) `string-upcase`(1) `string-downcase`(1) (ASCII letters only)
`string->number`(1: `#f` unless the whole string matches `-?[0-9]+` and fits int64) `number->string`(1)
`string->symbol`(1) `symbol->string`(1) `string->list`(1: list of 1-character strings) `list->string`(1: list
of strings, concatenated) `string-join`(2: `(string-join list sep)`) `string-split`(2: separator must be a
1-character string, else `string-split: separator must be one character`; splits at every occurrence, so
`"a,,b"` gives `("a" "" "b")` and `""` gives `("")`) `string-contains?`(2: `(string-contains? s sub)`).

Other: `display`(1) `write`(1) `newline`(0) `void`(0) `error`(1+).
`(error "msg" v...)` raises the runtime error whose message is `msg` followed by a space and the `write` form
of each extra argument; the first argument must be a string (`error: expected string, got V` otherwise).

## Errors

An error that is not caught by `try` ends the program: first, if output so far is non-empty and does not end with
a newline, a newline is printed; then `error: MESSAGE` and a newline. Nothing else is evaluated. The exit status
stays 0.

Runtime error messages, all exact: `unbound variable: NAME`, `not a procedure: V`, `wrong number of arguments to
NAME: expected E, got N`, `NAME: expected KIND, got V`, `division by zero`, `integer overflow`,
`recursion limit exceeded`, `NAME: index out of range`, `string-split: separator must be one character`, and
user messages from `error`. Syntax errors (`syntax error: ...`) are listed in *Reader* and *Special forms*.

## Example

Input:

    (define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
    (display (fact 10)) (newline)
    (display (try (quotient 1 0) (lambda (m) m))) (newline)
    (display "x")
    (car 5)

Output:

    3628800
    division by zero
    x
    error: car: expected pair, got 5
