# Bracket checker

For each line of standard input, check whether its brackets `()`, `[]`, `{}` are balanced.
All other characters are ignored but still count toward positions (1-based, per line).

For each line print one line:

- `ok` if the brackets are balanced (including a line with no brackets, or an empty line).
- `error N` otherwise, where `N` is:
  - the position of the first closing bracket that has no matching opener of the same kind
    on top of the stack (either nothing is open, or the wrong kind is open); or
  - if the scan finishes with openers still unclosed, the position of the *earliest* such opener.

A final line without a trailing newline is still a line. If the input ends with a newline,
there is no extra empty line after it.

Example:

    (a[b]c)
    (]
    ((x)

Output:

    ok
    error 2
    error 1
