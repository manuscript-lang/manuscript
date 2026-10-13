# Calculator

For each non-blank input line, evaluate an integer expression and print the result.

Grammar: non-negative integer literals, binary `+ - * /`, unary `-`, parentheses, and spaces/tabs
anywhere between tokens. `*` and `/` bind tighter than `+` and `-`; operators of equal precedence
associate left; unary minus binds tighter than `*` (so `-2*3` is `-6`, and `--4` is `4`). Division
truncates toward zero (`-7/2` is `-3`). Arithmetic is on signed 64-bit integers; tests never overflow.

Output per line:

- the result as a decimal integer;
- `error: division by zero` if a division by zero is evaluated (every division is evaluated; there is no short-circuiting);
- `error: syntax` for anything else invalid (empty parentheses, dangling operator, unbalanced
  parentheses, unknown characters, two adjacent numbers, ...).

A line that is empty or only whitespace produces no output. A division by zero in a line that is also a
syntax error reports the syntax error.

Example input:

    1 + 2 * 3
    (1+2)*3
    10 / (5 - 5)
    2 +
    -7 / 2

Output:

    7
    9
    error: division by zero
    error: syntax
    -3
