[Wiki](../index.md) › [Compiler and build](index.md)

# The C lowering holds statement temporaries and reads `xs[i]` as an index

- `xs[i]` parses as a type application (`MS_E_APPLY` with a `value`) until a name says `xs` is a value. `ms_expr_index` (`ast.h`) returns the receiver and index of either spelling; the checker (`ms_body_index`, receiver must be a local), both ownership walkers and `lst_index` use it. Any new walker over expressions needs the same case or it silently declines every non-literal index.
- Rust drops owned temporaries at the end of their statement, newest first, and at a `return` through the scope exit (no position). `lb_hold_temp` does the same for owned call arguments; inside a condition, a match arm or the right side of `and`/`or` the temporary is dropped at once. Dropping after each call matches Rust only while a statement has one temporary.
- `for x in list` (`lst_for`) reads the length once before the loop and holds the list in a variable; a list the loop made is owned by a scope around the loop, as Rust does.
- A `var` list that is returned is wrapped in an `Optional` by Rust (`opt.some`, `opt.unbox`, `opt.none_owned`); the C lowering declines such a function until it makes the same shape.
