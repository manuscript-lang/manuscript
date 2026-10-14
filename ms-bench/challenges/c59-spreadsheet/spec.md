# spreadsheet

Implement a spreadsheet engine driven by a script of commands on stdin: cells hold numbers, text, booleans or formulas; formulas reference cells and ranges and call functions; the engine tracks dependencies, detects cycles, recomputes only what is affected by a change, copies formulas with reference adjustment, and imports/exports CSV. The program always exits with status 0; all errors are printed on stdout.

## Script format

Each line of stdin is a command. Blank lines and lines starting with `#` (after leading whitespace) are ignored. For every command print `> ` followed by the line with trailing whitespace removed, then execute it. The command word is the first whitespace-separated token. Command words are case-sensitive and lowercase.

`import CELL` is followed by a *block*: the raw lines after it up to (not including) a line that is exactly `.`, or the end of input. The block is consumed by every `import` command, even one that fails with an error.

## Grid, references and cell inputs

The grid has columns `A`..`Z` and rows `1`..`999`. A *cell reference* argument of a command is one letter (either case) followed by one to three digits, without leading zeros, with a row from 1 to 999; anything else is `error: bad cell reference 'TEXT'` (TEXT as written). A *range argument* is a cell reference or two cell references joined by `:`; the corners may be given in any order (the range is normalized to the rectangle they span); anything else is `error: bad range 'TEXT'`.

`set CELL VALUE...`: VALUE is the rest of the line after the cell token with leading and trailing whitespace removed (inner spacing is kept). The cell's content is decided by the VALUE:

- empty: the cell is cleared;
- starts with `=`: a formula (the text after `=` is the formula source);
- starts with `'`: text; the apostrophe is not part of the text (`'123` is the text `123`);
- matches the number grammar `[+-]?(digits[.digits]|.digits)([eE][+-]?digits)?` (plus `digits.`) and is finite: a number (`007` is 7, `1,5`, `0x10`, `12abc` are not numbers);
- `TRUE` or `FALSE` in any letter case: a boolean;
- otherwise text.

The stored *raw text* is the trimmed VALUE; `show` prints it. `clear CELL` clears a cell. After `set` and `clear`, a recalculation runs (below) and `recalc N` is printed.

## Values and display

A value is empty, a number (double), text, a boolean, or an error. Error values: `#DIV/0!`, `#REF!`, `#NAME?`, `#VALUE!`, `#NUM!`, `#PARSE!` (formula could not be parsed), `#CYCLE!`.

Display text: text as is; booleans `TRUE`/`FALSE`; errors as written; numbers are formatted with exactly 10 digits after the decimal point (correctly rounded from the exact value of the double), then trailing zeros and a trailing `.` are removed, and `-0` becomes `0` (so `1/3` is `0.3333333333`, `1e15` is `1000000000000000`, `1e-11` is `0`). Numbers never use exponents. An arithmetic result that is infinite or NaN is the error `#NUM!`.

A formula whose final result is an empty cell becomes the number 0. A text value such as `=""` is empty text (displays as nothing) but is not an empty cell.

## Formulas

### Lexical rules

Whitespace (spaces, tabs) between tokens is ignored. Tokens:

- numbers: `digits[.digits]` or `.digits`, optionally followed by an exponent `e`/`E`, optional sign, digits (a trailing `.` after digits is allowed; `1E` with no exponent digits is the number `1` followed by an identifier and a parse error);
- strings: `"..."` where `""` inside stands for a quote; an unterminated string is a parse error;
- references: a word made of an optional `$`, one or more letters, an optional `$`, and one or more digits, not followed by an identifier character (letter, digit, `_`, `.`), `(` or `$`. A reference is *valid* when it has exactly one letter A..Z (either case), at most three digits without a leading zero, and row 1..999; an invalid reference (such as `AA1` or `A1000`) evaluates to `#REF!`. `$` marks the column or row as absolute (used by `copy`) and has no effect on evaluation;
- ranges: two references joined by `:` with no spaces;
- the literal `#REF!` (an error constant);
- identifiers: a letter or `_` followed by letters, digits, `_`, `.`; case-insensitive. An identifier followed by `(` is a function call; `TRUE`/`FALSE` are booleans; any other identifier evaluates to `#NAME?`;
- operators `+ - * / ^ & = <> < <= > >= ( ) ,`. Any other character is a parse error.

### Grammar and precedence (loosest first)

1. comparison `= <> < <= > >=` (left associative)
2. concatenation `&`
3. `+ -`
4. `* /`
5. unary `+` and `-` (prefix, may repeat)
6. `^`, right associative; its exponent may carry a unary sign (`2^-1`). Note unary minus is looser than `^`: `-2^2` is `-4`, and `2^3^2` is `512`.
7. primaries: number, string, boolean, reference, range, `#REF!`, identifier, function call `NAME(arg, ...)`, parenthesized expression.

Any syntax error (missing operand, unbalanced parentheses, empty argument such as `SUM(1,)`, trailing tokens) makes the cell's value `#PARSE!`. A function call with no arguments is allowed syntactically.

### Evaluation semantics

- A *range* used anywhere except as a direct function argument (in the functions that accept ranges) evaluates to `#VALUE!`.
- **Number coercion** (used by arithmetic and numeric arguments): a number is itself; TRUE is 1 and FALSE is 0; an empty cell is 0; text must match the number grammar above after trimming surrounding whitespace, else `#VALUE!`; an error stays that error.
- Binary operators evaluate both operands, then check them left to right; the first operand that is an error or fails coercion decides the result. `/` by zero is `#DIV/0!`. `^` is the power function.
- **String form**: numbers as displayed, booleans `TRUE`/`FALSE`, text itself, empty as the empty string. `&` joins string forms (an error operand, left first, is the result).
- **Comparison**: errors propagate (left first). If one side is empty it becomes the zero value of the other side's type (0, empty text, or FALSE); two empties are equal. Values of different types order as number < text < boolean. Numbers compare numerically, text by bytes (case-sensitive), booleans FALSE < TRUE.
- **Boolean coercion** (IF, NOT, AND, OR): number is true if nonzero; boolean itself; text `TRUE`/`FALSE` in any case; empty is false; other text is `#VALUE!`.
- Function names are case-insensitive. An unknown function is `#NAME?` (it is only an error when that call is actually evaluated; arguments are not evaluated first).
- Function arguments marked *scalar* below must not be bare ranges (a range there gives `#VALUE!`).

### Functions

In the aggregate functions, the argument *items* are collected in order: a range argument contributes its cells in row-major order, any other argument contributes its value. Items from a range are *range items*; the others are *direct items* (including a reference to one cell).

- `SUM`, `AVERAGE`, `MIN`, `MAX`, `PRODUCT`, `MEDIAN` (at least one argument, else `#VALUE!`): any error item returns that error (first one). A direct item is number-coerced (failing coercion gives `#VALUE!`; so direct text, TRUE and empty cells take part as numbers); range items count only if they are numbers (text, booleans and empty cells are skipped). Sums and products accumulate in item order, starting from 0 (1 for PRODUCT). `AVERAGE` is the sum divided by the count of numbers (none: `#DIV/0!`). `MIN`/`MAX` of no numbers is 0. `PRODUCT` of no numbers is 0. `MEDIAN` sorts the numbers (even count: mean of the two middle ones); none gives `#NUM!`.
- `COUNT`, `COUNTA` (at least one argument): count items that are numbers / items that are not empty. Errors never propagate (an error item counts for COUNTA, not for COUNT).
- `IF(c, a [, b])` (2 or 3 arguments): `c` scalar, boolean-coerced (an error is returned). Only the chosen branch is evaluated (as a scalar). A missing `b` is FALSE.
- `IFERROR(a, b)`: evaluate `a` (scalar); if it is an error evaluate and return `b`, else `a`.
- `CHOOSE(i, v1, v2, ...)` (at least 2 arguments): `i` is number-coerced and floored; if it is outside `1..n` the result is `#VALUE!`; only the chosen value is evaluated.
- `AND`, `OR` (at least one argument): evaluates all items in order without short-circuit; an error item returns that error; range items that are text or empty are skipped; the other items are boolean-coerced; if no item took part the result is `#VALUE!`.
- `NOT(x)`: scalar, boolean-coerced.
- `ABS(x)`, `INT(x)` (floor), `SQRT(x)` (negative gives `#NUM!`): scalar, number-coerced.
- `POW(a, b)`: like `^`. `MOD(a, b)`: `a - b*floor(a/b)`; `b = 0` gives `#DIV/0!`.
- `ROUND(x [, d])`: `d` defaults to 0 and is truncated toward zero; `|d| > 15` gives `#NUM!`; the result is `round(x * 10^d) / 10^d` computed in IEEE double arithmetic, rounding halves away from zero.
- `LEN(x)`: number of characters (code points) of the string form. `UPPER(x)`, `LOWER(x)`: ASCII letters only. `TRIM(x)`: collapse every run of whitespace into one space and remove leading and trailing whitespace.
- `LEFT(s [, n])`, `RIGHT(s [, n])` (`n` defaults to 1, floored; negative gives `#VALUE!`; larger than the length is clamped).
- `MID(s, start, len)`: `start` floored must be >= 1 and `len` floored >= 0, else `#VALUE!`; a start beyond the end gives empty text.
- `CONCAT(a, ...)` (at least one argument): string forms of all items (ranges flattened row-major) joined; an error item is returned.
- `SUBSTITUTE(s, old, new)`: replace every occurrence of `old` by `new`; empty `old` returns `s` unchanged.
- `VALUE(x)`: scalar; text is parsed with the number grammar after trimming (failure `#VALUE!`); numbers pass through; TRUE/FALSE are 1/0; empty is 0.
- `ISERROR`, `ISBLANK`, `ISNUMBER`, `ISTEXT` (one argument): the argument is evaluated as a scalar (a bare range counts as the error `#VALUE!`); `ISBLANK` is true only for an empty cell.
- `ROW(ref)`, `COLUMN(ref)`: the argument must be written as a reference or range (otherwise `#VALUE!`); an invalid reference gives `#REF!`; the result is the row/column number of the (first) reference. The argument is not evaluated and creates no dependency.
- `INDEX(range, r [, c])`: the first argument must be written as a range with a colon, i.e. `A1:C2` or `B2:B2` (anything else, including a lone cell reference such as `INDEX(A1, 1)`, a computed value, or a function call, is `#VALUE!`; invalid corners `#REF!`). With two arguments and a one-row range, `r` is the column index; with two arguments otherwise it is the row index and the column is 1; with three, row and column. Indexes are floored, 1-based; out of bounds gives `#REF!`. The result is the cell's value.
- `COUNTIF(range, criterion)`: the first argument must be written as a range with a colon (`A1:A7`, `B2:B2`); anything else, including a lone cell reference such as `COUNTIF(A1, 5)` or a constant such as `COUNTIF(5, 5)`, is `#VALUE!`. The criterion is evaluated as a scalar (errors returned). If it is text, a leading operator from `>=`, `<=`, `<>`, `>`, `<`, `=` (tried in that order; default `=`) is removed and the rest is the operand: a number if it matches the number grammar, else text. A non-text criterion is itself the operand, with operator `=`. A cell is *comparable* when its type (empty, number, text, boolean, error) equals the type of the operand; comparable cells are compared with the comparison rules above and counted when the operator holds. A non-comparable cell is counted only for `<>`, and only if it is not empty.

## Dependencies, cycles and recalculation

A formula's *precedents* are all cells named by valid references and by ranges (every cell of the rectangle, empty or not) that appear anywhere in its source, in every branch (also in unevaluated arguments of `IF`, `IFERROR`, `CHOOSE`), except inside the argument of `ROW`/`COLUMN`. Parse-error formulas have no precedents. A cell *depends on* its precedents; *dependents* are the inverse relation.

A formula cell that lies on a cycle of the dependency graph (including a formula that references itself, directly or through a range) has the value `#CYCLE!`. Other cells depending on it evaluate normally and simply see that error value as an operand (so `IFERROR` can catch it).

After a `set`/`clear`/`import`/`copy`, the cells that changed are the ones assigned. The *affected* cells are the changed cells that are now formulas plus every formula cell that transitively depends on a changed cell. Each affected formula cell is evaluated exactly once, after all of its affected precedents (cycle members are just assigned `#CYCLE!`). Unaffected cells keep their values. The command prints `recalc N`, where N is the number of affected formula cells (cycle members and parse-error formulas included, constants never). A cumulative counter `evals` adds every N.

## Commands

- `get CELL`: print the display text of the cell's value, or `(empty)` for an empty cell.
- `show CELL`: `NAME: (empty)`; for a constant `NAME: RAW`; for a formula `NAME: RAW => VALUE`, where NAME is the canonical reference (uppercase) and RAW the stored raw text.
- `print [RANGE]` and `export [formulas|values] [RANGE]`: print the rectangle row by row. The default range is from `A1` to the largest column and row among non-empty cells; if the sheet is empty print `(empty sheet)`. `print` joins display texts with ` | `. `export` prints CSV: fields joined with `,`; a field that contains `,`, `"`, a newline or a carriage return, or starts or ends with a space, is wrapped in double quotes with inner quotes doubled; empty cells are empty fields. `export formulas` uses each cell's raw text instead of its value (empty cell: empty field). At most one range and one of the words `formulas`/`values`; `print` rejects `formulas`. Errors: `usage: print [RANGE]` / `usage: export [formulas] [RANGE]`.
- `import CELL` (block): parse the block as CSV and assign the fields starting at the cell, rows downward, columns rightward. CSV rules: records end at newlines (the block lines joined by `\n`); a `"` starts a quoted section that lasts until the next lone `"` (inside it `""` is a literal quote and commas and newlines are literal); carriage returns outside quotes are ignored; completely blank records are skipped. Each field is interpreted exactly like the VALUE of `set` (empty field clears, `=` formula, number, boolean, `'text`, text), even if it was quoted. If the block would not fit in the grid (`import out of range`) nothing changes. Otherwise print `imported R rows, C columns; recalc N` with R the number of records and C the largest number of fields in a record. Argument errors: `usage: import CELL`, `bad cell reference`.
- `copy SRC DST`: SRC is one cell, DST a range. The content of SRC is captured first, then assigned to every cell of DST in row-major order: an empty SRC clears; a constant is copied as is; a formula is *shifted* by (destination column - SRC column, destination row - SRC row). Shifting tokenizes the formula source as above (a source that cannot be tokenized is copied unchanged) and rewrites reference tokens only (never text inside strings): a valid reference is rewritten in canonical form (uppercase letter, `$` markers kept), its column moved unless it has a `$` before the letter, its row moved unless it has a `$` before the digits; if the new column is outside A..Z or the row outside 1..999 the reference is replaced by `#REF!`. For a range, both corners are shifted independently and, if either leaves the grid, the whole range is replaced by `#REF!`. Invalid reference tokens are left unchanged. Everything else in the source is kept character for character. Then one recalculation runs for all assigned cells and `recalc N` is printed.
- `precedents CELL`, `dependents CELL`: the direct precedents of the cell's formula, or all transitive dependents of the cell, as space-separated cell names sorted by row then column (so `B1` before `A2`); `(none)` if empty. (A cell on a cycle is its own dependent.)
- `stats`: `cells N formulas M evals E` where N is the number of non-empty cells, M the number of formula cells, E the cumulative evaluation count (initially 0). Extra arguments are ignored.

## Errors

A failing command prints one line `error: MESSAGE` and changes nothing. Messages: `bad cell reference 'X'`, `bad range 'X'`, `unknown command 'WORD'`, `import out of range`, and these usage lines: `usage: set CELL VALUE`, `usage: clear CELL`, `usage: get CELL`, `usage: show CELL`, `usage: copy SRC DST`, `usage: import CELL`, `usage: precedents CELL`, `usage: dependents CELL`, `usage: print [RANGE]`, `usage: export [formulas] [RANGE]`. Argument counts are exact: `get`, `show`, `clear`, `precedents`, `dependents` and `import` take exactly one argument, `copy` exactly two (any other count, zero or too many, is the usage line, e.g. `clear A1 A2` and `get A1 B1` are `error: usage: clear CELL` / `error: usage: get CELL` and change nothing); `set` takes a cell and then any VALUE, so only a bare `set` is `error: usage: set CELL VALUE`, while `set A1` (no value) is an empty VALUE and clears A1 and recalculates as usual; `stats` ignores extra arguments. For `set`, the cell argument is checked after the usage check; for `copy`, SRC is checked before DST; for `import`, the block is consumed first.
