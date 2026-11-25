[Wiki](../index.md) › [Standard-library design](index.md)

# Python shapes are adopted where they remove unwrapping or index arithmetic

Decision (Chinmay, 2026-11-16): borrow a Python stdlib shape only when it measurably cuts tokens or wrong programs, and give a bad caller value `none` or an error, never a fault. Adopted: `String.split_once`/`rsplit_once` (`SplitParts` with `before`/`after`, `none` for a missing or empty separator), `List.counts()` (Counter), `math.pow_int` (`none` on overflow or a negative exponent), `math.divmod` (floor, like Python; `none` for a zero divisor or `min_int / -1`), `math.gcd/lcm/isqrt`, `path.stem/with_extension`, `fs.exists` (`Bool!`: ENOENT and ENOTDIR are `false`, other failures are errors), plain `String.repeat`.

Already better than Python, so unchanged: `min`/`max` return an optional, `Map.update`/`add_default`/`get_or` cover `defaultdict`, `cut_prefix`/`cut_suffix` return `String?` (Python's `removeprefix` cannot say whether it matched).

`List.take_while`/`drop_while` were added as methods beside `take`/`drop`. Not done: `fs.read_lines(path)`, because whole-file reads are promise-based and a line-list wrapper needs its own decision.

Evidence: [python-shapes fixture](../../../tests/lang/stdlib/python-shapes.ms); proposal in the project files, `design/proposals/python-stdlib-shapes-2026-11-17.md`.
Verify: `ms test tests/lang/stdlib/python-shapes.ms`.
