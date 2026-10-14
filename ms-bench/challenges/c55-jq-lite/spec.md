# jq-lite

Implement a command-line JSON processor in the spirit of `jq`: a small expression language (filters) that is run over a stream of JSON values. The program text and the JSON inputs both arrive on standard input. Your program must always exit with status 0; every error is reported on standard output as described below.

This spec defines the exact behavior to implement. It is close to jq 1.7 but it is NOT identical; where this document says something, follow this document, not real jq.

## Input

Line 1 of stdin is the *program line*. Everything after the first newline is the *input text*.

The program line may start with option tokens. An option token is exactly `-r `, `-s `, or `-n ` (dash, letter, one space), and any number of them may be stacked in any order at the very start of the line. After stripping them, the rest of the line (trailing `\r` removed) is the filter program.

- `-r`: a string result is printed raw (the string content followed by `\n`, no quotes, no escaping). Non-strings are printed as compact JSON.
- `-s`: slurp. All input values are collected into one array and the program runs once on that array (an empty input gives `[]`).
- `-n`: the program runs exactly once with input `null`, and the input text is ignored entirely (it is not even parsed).

The input text is a stream of zero or more JSON values separated by optional whitespace (space, tab, `\n`, `\r`). The program runs once for each value (unless `-s` or `-n`), in order. Values may be adjacent only when unambiguous, for example `1 2`, `[1][2]`, `"a""b"`, `{}{}`. Numbers must follow strict JSON syntax (no leading `+`, no leading zeros such as `01`, no `.5`, no `5.`, no `NaN`/`Infinity`). Strings follow strict JSON: raw control characters below 0x20 are invalid, escapes are `\" \\ \/ \b \f \n \r \t \uXXXX`; a valid surrogate pair `😀` becomes one character, a lone surrogate becomes U+FFFD. Duplicate object keys: the later value replaces the earlier value but the key keeps its original position.

If the input text is not valid JSON, all values before the invalid point have already been processed (and printed); then the single line `error: invalid JSON input` is printed and processing stops. With `-s` nothing is run in that case, only the error line is printed.

## Output

For each result of the program, in order, one line is printed: the compact JSON of the value (no spaces anywhere, object keys in insertion order, no sorting), except a string under `-r`.

**JSON text rules.** Strings are printed as UTF-8, escaping only `"` as `\"`, `\` as `\\`, newline `\n`, tab `\t`, carriage return `\r`, backspace `\b`, form feed `\f`, and any other character below 0x20 or equal to 0x7f as `\u` plus four lowercase hex digits. Non-ASCII characters are printed as-is. `/` is not escaped.

**Numbers** are IEEE-754 doubles. A number that is integral and has absolute value below 1e17 prints as an integer with no decimal point (so `3.0` prints `3` and `-0` prints `0`). Any other number prints as the shortest decimal that round-trips, in plain notation without an exponent (`0.1`, `0.30000000000000004`, `0.0005`). Positive infinity prints `1.7976931348623157e+308`, negative infinity `-1.7976931348623157e+308`, NaN prints `null`.

**Errors.** If evaluating the program on one input raises an error that nothing catches, output for that input stops at once, and a line is printed: `error: MESSAGE` if the error value is a string (MESSAGE is the string, unescaped), or `error: (not a string): JSON` otherwise, where JSON is the compact JSON of the error value. Processing then continues with the next input value. Results printed before the error stay printed. Errors in the program itself (see "Compile-time errors") are printed before any input is read, once, and nothing else is printed.

## Values and ordering

Types: `null`, `boolean`, `number`, `string`, `array`, `object`. `false` and `null` are falsy; everything else (including `0`, `""`, `[]`, `{}`) is truthy.

Sort order (used by `sort`, `unique`, `group_by`, `min`, `max`, comparison operators, ...): `null < false < true < numbers < strings < arrays < objects`. Numbers compare numerically; strings compare by UTF-8 byte order; arrays lexicographically element by element (a proper prefix is smaller); objects first compare their sorted key lists as arrays, then, if equal, their values in sorted key order. `==` and `!=` are `compare == 0` / `!= 0` under this order.

Sorts are stable.

## Syntax

Whitespace (space, tab, newline, `\r`) may appear between any two tokens. There are no comments. Precedence, from loosest to tightest:

1. `|` (pipe, right associative), and `def` / `as` bindings which extend as far right as possible
2. `,` (comma)
3. `//` (alternative, right associative)
4. assignment operators `=  |=  +=  -=  *=  /=  %=  //=` (non-associative: chaining them without parentheses is a syntax error); the right-hand side is parsed at the `or` level, i.e. it cannot contain a bare `,`, `//` or `|`. So `.a = 1 // 2` means `(.a = 1) // 2` and `.a = 1, .b = 2` is two assignments, and `.a = 1 | .b = 2` is a pipe of two assignments.
5. `or`
6. `and`
7. comparison `== != < <= > >=` (non-associative: `1 < 2 < 3` is a syntax error)
8. `+ -` (left associative)
9. `* / %` (left associative)
10. unary minus `-X` (applies to a following postfix term; `- -1` is allowed)
11. postfix: `.foo`, `."foo"`, `[e]`, `[]`, `[a:b]`, `?`, and `X as PATTERN | body`

Terms:

- `.` identity; `..` is `recurse` (all values, depth-first, parent before children).
- `.foo`, `.foo.bar`, `."foo bar"`, `.["foo"]`, `.[0]`, `.[-1]`, `.[]`, `.[2:4]`, `.[:3]`, `.[-2:]`. A postfix may follow any term: `(expr).foo`, `.a[0].b`, `f[1]`, `.[]?`. `.foo` identifiers match `[A-Za-z_][A-Za-z0-9_]*`. Postfix suffixes (`[`, `.name`, `."str"`, `?`) must follow the preceding term immediately, with no whitespace (`. [0]` and `.a [0]` are syntax errors). The form `.a.[0]` (dot before bracket) is allowed.
- Literals: numbers (`12`, `1.5`, `.5`, `1e3`, `1E-2`), strings, `true`, `false`, `null`.
- Strings `"..."` with escapes `\" \\ \/ \b \f \n \r \t \uXXXX` (same surrogate rules as above) and interpolation `\( pipe )`, whose result is converted with `tostring` and spliced in; if interpolated expressions yield multiple results, the string yields one result per combination (see "Generators"). Raw newlines inside strings are allowed.
- Format strings: `@text @json @csv @tsv @html @uri @base64 @base64d`. `@name` alone is a filter applied to `.`; `@name "string \(interp)"` applies the format to each interpolated value only (literal text is untouched).
- Array construction `[ pipe ]` collects all results; `[]` is empty.
- Object construction `{ ... }` with entries separated by commas: `a: v`, `"a b": v`, `(expr): v` (expr must produce a string), `$name` (same as `name: $name`), `a` (same as `a: .a`), `"a"` (same as `"a": .["a"]`), `@fmt "..." : v`. The entry value `v` is parsed as: alternatives and above with `|` allowed, but NOT `,` (so `{a: 1 | 2, b: 3}` is `{a: (1|2), b: 3}`). Keys may be bare words including keywords. If a key or value expression yields several results, the object construction yields the cartesian product (see Generators).
- `( pipe )`, `if c then a (elif c2 then b)* (else d)? end` (a missing `else` means identity; the condition may yield multiple results, giving a result per condition value), `try BODY (catch HANDLER)?` where BODY and HANDLER are postfix terms, `reduce SRC as PAT (init; update)`, `foreach SRC as PAT (init; update)` and `foreach SRC as PAT (init; update; extract)`, function calls `name`, `name(a; b)`, variables `$name`, and `def` definitions.
- `X?` is exactly `try X`.
- Keywords (not usable as function, variable, or parameter names): `def if then elif else end as reduce foreach try catch and or label import include __loc__`. `label`, `import`, `include`, and `__loc__` are reserved but have no meaning; any use is a syntax error.

Any text that does not parse (unbalanced brackets, a missing `then`/`end`, trailing junk, an empty program, unknown format name, bad escape, unterminated string, ...) produces the single output line `error: syntax error` and nothing else.

### Variables, patterns, `as`

`SRC as PATTERN | body` evaluates SRC; for each result it binds the pattern and runs `body` on the *original* input `.`. Patterns: `$x`; array pattern `[$a, $b, ...]` (elements may be nested patterns; a missing element binds `null`; matching a non-array non-null value raises `Cannot index T with number`); object pattern `{a: $x, "b": $y, (expr): $z, $name, $name: pattern}` (a missing key binds `null`; a non-object non-null value raises `Cannot index T with string "key"`). `{$name}` binds `$name` to `.name`; `{$name: pat}` binds `$name` to `.name` and also matches `pat` against it. A pattern may use variables bound earlier in the same pattern inside `(expr)` keys. Alternative patterns (`?//`) are not supported.

`reduce` and `foreach` patterns work the same way. For `reduce`, the update is evaluated on the current state for every source result; the state becomes the *last* output of the update, or `null` if the update produced nothing. `reduce` of no source results returns the init. If init yields several results, the whole reduce yields one result per init result. `foreach` emits, for each source result and each output of the update, the extract-expression applied to that update output (or the output itself with no extract); the state becomes the last output of update.

### Functions

`def name: body;` and `def name(p1; p2): body;` may appear wherever a pipe may start (before any pipe expression), including inside bodies and inside parentheses. A parameter `f` is a closure (a filter evaluated at its call site in the caller's scope, on the input the callee uses it with). A parameter written `$f` is a value parameter: `def g($a): body` behaves as `def g(a): a as $a | body`, so both `a` (as a filter) and `$a` are available, and multiple results of the argument yield multiple results of the call (cartesian product, left argument outermost). Functions are identified by name AND arity; the same name with different arities are independent. Definitions are lexically scoped and may be recursive (a function can call itself and any function defined earlier; a later redefinition shadows an earlier one for code that follows it). Iteration through `until`, `while`, `repeat`, `recurse`, `range`, `limit`, `reduce`, and `foreach` must handle at least 10000 steps; plain user recursion is only exercised to depth 200.

## Compile-time errors

Before any input is processed the program is checked statically:

- a reference to an unbound variable `$name` gives `error: $name is not defined`
- a call to an unknown function gives `error: NAME/ARITY is not defined` (for example `nosuch(1)` gives `nosuch/1 is not defined`; a zero-argument call gives `nosuch/0 is not defined`)

When several apply, the first one met when scanning the program left to right in source order is reported. For `def f: body; rest`, the body of `f` is checked before `rest`. Within `reduce`/`foreach`, the source and init are checked in the outer scope before the update/extract see the pattern variables. These errors are printed once, nothing else is printed, and no input is read (so an invalid JSON input does not matter).

Syntax errors take priority over those (a program that does not parse reports `error: syntax error`).

## Generators

Every filter produces zero or more results. The rules for combining are:

- `A | B`: for each result of A, run B on it.
- `A , B`: all results of A on `.`, then all of B on `.`.
- Binary operators `A op B` (arithmetic, comparison): for each result `b` of B (outer loop) and for each result `a` of A (inner loop), emit `a op b`. So `(1,2) - (10,20)` is `-9, -8, -19, -18`.
- `A and B`, `A or B`: for each result of A: if decided by A alone (`false`/falsy for and, truthy for or), emit that boolean; otherwise for each result of B emit its truthiness as a boolean. `(true,false) and (true,false)` is `true,false,false`.
- `A // B`: emit every *truthy* result of A; if there was none, emit all results of B. Errors raised while evaluating A are suppressed (as if A were `try A`); if A has already produced a truthy result and then errors, the output simply ends there. Errors raised by code *downstream* of `//` are not affected.
- Object construction and string interpolation take the cartesian product with the **later** parts as the outer loop and the earlier parts varying fastest: `{a:(1,2), b:(3,4)}` yields `{a:1,b:3}`, `{a:2,b:3}`, `{a:1,b:4}`, `{a:2,b:4}`, and `"\(1,2)-\(3,4)"` yields `"1-3"`, `"2-3"`, `"1-4"`, `"2-4"`. (Within one object entry the key is the outer loop and the value the inner.)
- Function calls with `$`-parameters: the **first** `$`-argument is the outer loop, so `def f($a; $b): [$a,$b]; f(1,2; 3,4)` yields `[1,3]`, `[1,4]`, `[2,3]`, `[2,4]`.
- `.[e]`, `.[a:b]`: the index/bound expressions are evaluated against the input `.` of the whole expression (not against the indexed term). For `T[e]`: for each result of `e` (outer), for each result of `T` (inner). For `T[a:b]`: `a` is the outer loop, then `b`, then `T`: `[10,20,30][(0,1):(2,3)]` yields `[10,20]`, `[10,20,30]`, `[20]`, `[20,30]`.
- `reduce`/`foreach`/`limit`/`first`/`until`/etc. stop pulling results from a generator as soon as they are satisfied (for example `first(range(1000000000))` or `limit(3; repeat(1))` must terminate immediately).

## `try` / `catch` and errors

`try BODY` runs BODY; if it raises an error, the error is swallowed: results emitted before the error stay, and nothing more is emitted from BODY. With `catch H`, the handler H is run on the error value (the message string, or whatever value was passed to `error`) and its results are emitted. Errors raised by code *downstream* of the `try` (the consumer of its results) are NOT caught by it: in `(try (1,2)) | error("x")` the error passes through the `try` and is uncaught. The same holds for the left side of `//`. `error` (arity 0) raises the input as the error; `error(msg)` raises `msg` (any value, including `null`). `try error(null) catch .` yields `null`. `.a?` is `try .a`. An error value that is an object is printed with the `(not a string)` form when uncaught.

## Paths and assignment

Some filters are *path expressions* and can be used with `path(f)`, `paths`, assignment, and `del`. A path expression is built from: `.`, `..`, `.foo`, `.[e]`, `.[]`, `.[]?`, `getpath(p)`, `select(f)`, `if/then/else` and `//` and `,` and `|` composing path expressions, `first(f)`, `limit(n; f)`, `recurse`, `empty`, `error`, `try`/`?`, and calls of user-defined functions or builtins written in terms of these (`map_values`, `recurse(f)`, `walk` etc. are defined with these). Slices `.[a:b]` are not usable inside path expressions (raises `Slices are not supported in path expressions`). If a path expression is applied to a value that is not a path (for example `path(1)` or `path(.a | tostring)`), the error is `Invalid path expression with result JSON` where JSON is the compact JSON of that value.

- `path(f)`: emits for each result of f its path as an array of keys (strings and integers).
- `getpath(p)`: value at path array `p`; `null` if some prefix is `null`; errors from impossible indexing propagate (`getpath(["a","b"])` on `{"a":1}` raises `Cannot index number with string "b"`). If `p` is not an array: `Path must be specified as an array`.
- `setpath(p; v)`: returns the input with the value at `p` replaced; missing intermediate containers are created (`null` becomes an object or an array depending on the key type). Setting an array index beyond the end pads with `null`. Negative indices count from the end; a negative index that is still out of range raises `Out of bounds negative array index`. `setpath` on the wrong container type raises `Cannot index T with string "k"` or `Cannot index T with number`. A path component that is neither string nor number raises `Invalid path component JSON`.
- `delpaths(ps)`: deletes all the paths (applied from the lexicographically greatest path to the smallest, so deleting several array elements works as expected). Deleting a missing path is a no-op. A negative array index counts from the end (`delpaths([["l",-1]])` removes the last element; an out-of-range one is a no-op). Deleting the **empty path** `[]` is also a no-op: the input is returned unchanged (`delpaths([[]])` on `{"a":1}` gives `{"a":1}`, and so does `del(.)`; unlike jq it does not give `null`). A path whose prefix leads to `null` or to a missing key is a no-op; a path that continues into a scalar raises the scalar error for the final key (`delpaths([["a","b","c"]])` on `{"a":{"b":1}}` is `Cannot delete field at index of number`). `delpaths` of a non-array argument: `Paths must be specified as an array`; a path that is not an array: `Path must be specified as an array`. Deleting with a wrong key type: `Cannot delete field at object index of T` / `Cannot delete field at array index of T`; deleting from a scalar: `Cannot delete field at index of T`.
- `del(f)` is `delpaths([path(f)])`.
- `paths` is `path(..) | select(length > 0)`; `paths(f)` keeps paths whose value satisfies `f`; `leaf_paths` is `paths(scalars)`.

Assignment `LHS op RHS` where LHS is a path expression:

- `LHS = RHS`: RHS is evaluated on `.`; for **each result** of RHS, emit the input with all LHS paths set to that value.
- `LHS |= F`: for each path of LHS (all paths computed up front against the original input), the value at the path is replaced by the **first** result of F run on the old value; if F yields nothing, that path is deleted (all deletions happen at the end, after the other updates). Emits exactly one result.
- `LHS op= RHS` for `+ - * / %`: like `=` except that each LHS path is set to `old op rhs`, where RHS is evaluated on `.` (the original input), once per RHS result (so a multi-valued RHS gives multiple results).
- `LHS //= RHS`: sets each path to `old` if `old` is truthy, else to the RHS value.

When `LHS` yields no path, the input is returned unchanged.

## Operators

- `+`: `null + x` and `x + null` are `x`. numbers add; strings concatenate; arrays concatenate; objects merge (right wins, keys of left keep their positions, new keys are appended).
- `-`: numbers subtract; array minus array removes every element equal to any element of the right array.
- `*`: numbers multiply; string times number repeats the string (a number `n <= 0` gives `null`; a fractional `n` between 0 and 1 gives the string once; otherwise `ceil(n)` copies); number times string likewise; object times object is a deep merge (nested objects merged recursively, other right values replace).
- `/`: numbers divide (division by zero raises `division by zero`); string divided by string splits (same as `split`).
- `%`: both operands are truncated toward zero to integers; the result has the sign of the left operand (`-7 % 3` is `-1`, `7 % -3` is `1`); a zero right operand (after truncation) raises `division by zero`.
- Unary `-` on a non-number: `T cannot be negated`.
- Any other combination of operand types raises `T1 and T2 cannot be added` / `cannot be subtracted` / `cannot be multiplied` / `cannot be divided` (for `/` and `%`), where `T1`/`T2` are the type names (`null`, `boolean`, `number`, `string`, `array`, `object`) of the left and right operand.

## Indexing

- `null | .foo` and `null | .[0]` are `null`; `null` indexed with a string/number/null key gives `null`.
- Object with a string key: the value or `null`. Object with any other key type: `Cannot index object with T`.
- Array with a number key: the element at `floor(index)`, negative counts from the end, out of range gives `null`. Array with a string: `Cannot index array with string "KEY"`. Array with another type: `Cannot index array with T`.
- Any other value (boolean, number, string) with a string key: `Cannot index T with string "KEY"`; with a non-string key: `Cannot index T with T2`.
- `.[]` on an array or object emits all values (object values in insertion order); on anything else raises `Cannot iterate over T` (for null: `Cannot iterate over null`).
- Slices `.[a:b]`: on arrays and strings (strings are sliced by characters/code points) and `null` (gives `null`). A missing bound is the start/end. Bounds may be fractional or negative: the start is `floor`, the end is `ceil`; negative values add the length; then both are clamped to `[0, length]`, and an end before the start gives an empty result. Non-numeric (and non-null) bounds raise `Start and end indices of an array slice must be numbers`. Slicing any other type raises `Cannot index T with object`.

## Builtin functions

All of the following exist with exactly these arities. "Input" is `.`. `T` below is a type name.

**Core**: `empty`, `not`, `error`, `error(m)`, `select(f)`, `recurse`, `recurse(f)`, `recurse(f; cond)` (follow `f` while `cond` holds on each result), `range(n)`, `range(a; b)`, `range(a; b; step)` (numeric only: `Range bounds must be numeric`; step 0: `Range step must not be zero`; positive step counts up while `< b`, negative step counts down while `> b`; each argument may be a generator, with the first argument the outer loop), `limit(n; f)` (`n <= 0` gives nothing; non-number: `limit: expected number, got T`), `first(f)`, `first`, `last`, `last(f)`, `nth(n)`, `nth(n; f)` (negative `n`: `Out of bounds negative array index`), `until(cond; update)`, `while(cond; update)`, `repeat(f)` (`repeat` emits its input, then recurses into `f`'s results forever), `isempty(g)`, `any`, `all`, `any(f)`, `all(f)`, `any(gen; cond)`, `all(gen; cond)` (`any`/`all` short-circuit; `any` of nothing is `false`, `all` of nothing is `true`), `walk(f)` (bottom-up: children are transformed first, then `f` is applied to the rebuilt value), `map(f)` (`[.[] | f]`), `map_values(f)` (`.[] |= f`), `add` (sum of array elements or object values with `+` starting from `null`; an empty collection gives `null`; on null input `Cannot iterate over null`, on other scalars `Cannot iterate over T`), `add(f)`, `in(obj)`, `inside(v)`, `has(k)`, `contains(v)`, `toarray`.

**Collections**: `length` (null 0; boolean error; number absolute value; string number of characters; array length; object number of keys; otherwise `T has no length`, e.g. `boolean has no length`), `keys` (sorted keys of an object, or indices of an array; otherwise `T has no keys`), `keys_unsorted`, `has(k)` (object with string, array with number; otherwise `Cannot check whether T has a T2 key`), `contains(b)` (strings: substring; arrays: every element of b is contained in some element of the input of the same type; objects: every key of b exists and values contain; other: equal; different types raise `T1 and T2 cannot have their containment checked`), `sort`, `sort_by(f)`, `group_by(f)`, `unique`, `unique_by(f)`, `min`, `max`, `min_by(f)`, `max_by(f)` (keys are `[f outputs]` arrays; `min`/`max` of an empty array is `null`; ties: `min` and `min_by` return the first minimal element, `max` and `max_by` return the last maximal element), `reverse` (arrays and strings; `null` gives `[]`; otherwise `reverse: expected array or string or null, got T`), `flatten`, `flatten(depth)` (negative depth: `flatten depth must not be negative`), `transpose` (shorter rows padded with `null`), `to_entries` (`[{"key":k,"value":v}, ...]` in key insertion order; for arrays the keys are the numeric indices; other types raise as `keys_unsorted` does), `from_entries` (each element must be an object, else `from_entries: expected object, got T`; the key is the first truthy of the fields `key`, `k`, `name`, `Name`, `K`, `Key` (a non-string key is converted with `tojson`, so `null` becomes `"null"`), the value is the first present of `value`, `v`, `Value`, `V`, else `null`), `with_entries(f)` (`to_entries | map(f) | from_entries`), `indices(x)` / `index(x)` / `rindex(x)` (strings: character offsets of every occurrence, empty needle gives `null`; arrays: positions of the element, or starts of the sub-array when x is an array; `null` input gives `null`), and the path functions below.

The following type selectors keep their input when the type matches: `values` (not null), `nulls`, `booleans`, `numbers`, `strings`, `arrays`, `objects`, `iterables` (array or object), `scalars` (anything else). `type` returns the type name.

**Argument/type errors.** Several functions check the input and raise `NAME: expected KINDS, got T` where KINDS is the accepted type(s) joined by ` or `: `sort`, `unique`, `min`, `max`, `sort_by`, `group_by`, `unique_by`, `min_by`, `max_by` need an array (`sort: expected array, got object`); `floor ceil round sqrt abs` and `isnan` need a number (`floor: expected number, got string`); `ascii_downcase ascii_upcase startswith endswith split` need string input (and `startswith endswith split` also a string argument: `startswith: expected string, got number`); `explode` needs a string; `implode` needs an array of numbers (`implode: expected number, got T`); `join` needs an array (`join: expected array, got T`) and a string separator (`join: expected string, got T`); `fromjson` needs a string; `transpose` needs an array and rows that are arrays (`transpose: expected array, got T`); `pow` needs numbers.

**Math**: `floor`, `ceil`, `round` (half away from zero), `sqrt` (negative gives `null`), `abs`, `pow(a; b)` (non-finite result gives `null`), `infinite`, `nan`, `isnan`. `pow` with several results per argument: first argument is the outer loop.

**Strings**: `tostring` (strings unchanged, everything else compact JSON), `tonumber` (numbers unchanged; strings must match `-?digits(.digits)?([eE][+-]?digits)?` with at least one digit, else `Cannot parse "TEXT" as number` where TEXT is the string escaped as JSON; other types `tonumber: expected string or number, got T`), `tojson`, `fromjson` (invalid text raises `fromjson: invalid JSON text`), `ascii_downcase`, `ascii_upcase` (ASCII letters only), `explode` (array of code points), `implode`, `ltrimstr(x)` / `rtrimstr(x)` (remove a prefix/suffix if both are strings and it matches, else return the input unchanged), `startswith`, `endswith`, `split(sep)` (empty input string gives `[]`; empty separator splits into characters), `join(sep)` (elements `null` become the empty string, numbers and booleans their JSON text, strings as is; arrays or objects raise `join: cannot join T`).

**Formats** `@fmt` applied to value `v`:
- `@text`: `tostring`. `@json`: compact JSON.
- `@csv`, `@tsv`: input must be an array (else `T cannot be csv-formatted, only an array can be` / `... tsv-formatted ...`); elements: `null` is empty, booleans `true`/`false`, numbers as printed, strings quoted with `"` doubled for csv (and unquoted for tsv with `\` `\t` `\n` `\r` escaped as `\\ \t \n \r`); other element types raise `T is not valid in a csv row` (also for tsv). Fields joined with `,` (csv) or a tab (tsv).
- `@html`: `<`→`&lt;` `>`→`&gt;` `&`→`&amp;` `'`→`&#39;` `"`→`&quot;` applied to `tostring` of the value.
- `@uri`: percent-encode each UTF-8 byte of `tostring(v)` except `A-Z a-z 0-9 - _ . ~`, using uppercase hex `%XX`.
- `@base64`: standard base64 with padding of the UTF-8 bytes of `tostring(v)`. `@base64d`: decodes (padding optional); invalid input raises `JSON is not valid base64 data` where JSON is the compact JSON of the input.

## Checks the tests rely on (summary)

- Program errors go to stdout, exit status is always 0.
- Output is compared exactly (trailing whitespace ignored), so the order of results and the exact error text matter.
- Programs never read the environment, clock, files, or randomness.
