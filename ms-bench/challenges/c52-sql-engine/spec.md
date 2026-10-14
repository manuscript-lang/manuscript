# SQL engine

Implement a small in-memory SQL database. Standard input is a script of SQL statements. Statements are
executed in order against one database that starts empty. Every statement prints its result (or an error line)
to standard output. The exit status is always 0.

## Script structure

- Statements are separated by `;`. A `;` inside a string literal or a `--` comment does not separate. The last
  statement needs no `;`.
- A statement that is empty after removing whitespace and comments produces no output and is ignored.
- Each statement is lexed, parsed and executed independently. A failing statement prints one line
  `error: MESSAGE` and execution continues with the next statement. A failed statement never changes the database.

## Lexical rules

- Whitespace: space, tab, CR, LF. `--` starts a comment up to the end of the line. There are no block comments
  (`/* */` is a syntax error because `/` and `*` are operators).
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`. **Keywords are case-insensitive** and reserved (cannot be used as table,
  column or alias names): `SELECT FROM WHERE GROUP BY HAVING ORDER LIMIT OFFSET JOIN LEFT INNER ON AS AND OR NOT
  NULL IS LIKE IN BETWEEN INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY DISTINCT ASC DESC`.
  Table, column and alias names are **case-sensitive**. Function names and the type names `INT`, `TEXT` are
  case-insensitive and not reserved.
- Integer literals: decimal digits only (no sign; `-` is an operator). A literal above 9223372036854775807 is a
  syntax error. Programs keep all computed values inside the signed 64-bit range.
- String literals: `'...'` with `''` for a quote. Raw newlines are allowed.
- Operators and punctuation: `= <> != < <= > >= + - * / % || ( ) , .` (`!=` is the same as `<>`).
- Any other character, or an unterminated string, is `syntax error`.

Any parse failure produces exactly `error: syntax error`. A statement is checked for syntax **before** anything else
(a statement with a syntax error never reports a missing table).

## Statements

```
create := CREATE TABLE name '(' coldef (',' coldef)* ')'
coldef := name type (PRIMARY KEY | NOT NULL)*        type is INT or TEXT (any other word: syntax error)
drop   := DROP TABLE name
insert := INSERT INTO name ['(' name (',' name)* ')'] VALUES row (',' row)*
row    := '(' expr (',' expr)* ')'
update := UPDATE name SET name '=' expr (',' name '=' expr)* [WHERE expr]
delete := DELETE FROM name [WHERE expr]
select := SELECT [DISTINCT] item (',' item)*
          [FROM tref join*]
          [WHERE expr]
          [GROUP BY colref (',' colref)*]
          [HAVING expr]
          [ORDER BY expr [ASC|DESC] (',' expr [ASC|DESC])*]
          [LIMIT INTLIT [OFFSET INTLIT]]
item   := '*' | name '.' '*' | expr [AS name]
tref   := name [AS name | name]              (the optional second name is an alias)
join   := [INNER | LEFT] JOIN tref ON expr
colref := name | name '.' name
```

The statement must end after its last clause (extra tokens are a syntax error). `OFFSET` is only allowed after
`LIMIT`. `HAVING` may appear without `GROUP BY`.

### Expressions

```
expr    := or
or      := and (OR and)*
and     := not (AND not)*
not     := NOT not | cmp
cmp     := add [ (= | <> | != | < | <= | > | >=) add
               | IS [NOT] NULL
               | [NOT] LIKE add
               | [NOT] IN '(' expr (',' expr)* ')'
               | [NOT] BETWEEN add AND add ]            (at most one comparison per cmp: `1 = 1 = 1` is a syntax error)
add     := mul (('+' | '-' | '||') mul)*                 (left associative; `||` has the same level as `+`)
mul     := unary (('*' | '/' | '%') unary)*
unary   := '-' unary | primary
primary := INTLIT | STRING | NULL | colref | name '(' [DISTINCT] (expr (',' expr)* | '*')? ')' | '(' expr ')'
```

`*` as the sole argument is allowed only for `COUNT`. `DISTINCT` inside a call allows exactly one argument (on a non-aggregate function it is accepted and has no effect).
`name '(' ')'` (no arguments) parses; its argument count is checked later.

## Values and semantics

Stored values are INT (signed 64-bit), TEXT (bytes) or NULL. Expressions may also produce a boolean (from
comparisons, `AND`, `OR`, `NOT`, `IS NULL`, `LIKE`, `IN`, `BETWEEN`) or NULL. Booleans cannot be stored.

- Arithmetic `+ - * / %` and unary minus need INT operands; `/` truncates toward zero, `%` takes the sign of the
  dividend; `/` or `%` by zero is `division by zero`. `||` needs TEXT operands. NULL in any of these gives NULL
  (checked after nothing else: `NULL + 'a'` is NULL).
- Comparisons need operands of the same type (INT with INT or TEXT with TEXT, TEXT compared bytewise); a NULL operand
  gives NULL; otherwise mismatched types (including booleans) are `type error`.
- `AND`, `OR`, `NOT`, and the WHERE/HAVING/ON conditions require boolean or NULL; any INT/TEXT operand is
  `type error`. Three-valued logic: `false AND x` is false, `true OR x` is true (and the right side is **not
  evaluated** in those cases, so errors in it do not occur; in every other case, including a NULL or true left side of
  `AND` and a NULL or false left side of `OR`, the right side *is* evaluated and its errors occur:
  `SELECT 1 = 2 AND 1 / 0 = 1` is false but `SELECT 1 = 1 AND 1 / 0 = 1` and `SELECT NULL AND 1 / 0 = 1` are
  `error: division by zero`); `NULL AND true` is NULL; `NULL AND false` is false;
  `NULL OR true` is true; `NULL OR false` is NULL; `NOT NULL` is NULL.
- A WHERE/HAVING/ON condition keeps a row only when it is true (NULL and false drop it).
- `IS NULL`/`IS NOT NULL` never give NULL. `x LIKE p`: both TEXT (else `type error`; NULL gives NULL); `%` matches
  any run of bytes (including empty), `_` exactly one byte, other bytes literally; case-sensitive; whole-string match.
- `x IN (a, b, ...)`: evaluates `x` then each element in order; NULL if `x` is NULL; true if any element equals `x`;
  otherwise NULL if any element is NULL; otherwise false. Comparison of mismatched types is `type error`.
  `NOT IN` negates (NULL stays NULL).
- `x BETWEEN lo AND hi` is `x >= lo AND x <= hi` with the three-valued rules (both bounds evaluated); `NOT BETWEEN` negates.
- Functions (name case-insensitive, shown upper-case in messages): `UPPER(t)`, `LOWER(t)` (ASCII), `LENGTH(t)` (bytes),
  `ABS(i)`, `SUBSTR(t, start, len)` (1-based; the result is the bytes of `t` at positions `start .. start+len-1`
  clipped to the string, so `start < 1` shortens the result from the front: `SUBSTR('hello',0,3)` is `he`,
  `SUBSTR('hello',-1,4)` is `he`; empty when `len <= 0` or `start` is beyond the end), `COALESCE(a, b, ...)`
  (first non-NULL, at least one argument, any types; **all arguments are always evaluated**, left to right, with no
  short-circuiting, so `COALESCE(1, 1 / 0)` is `error: division by zero`). Scalar functions return NULL for a NULL argument (except
  COALESCE) and are `type error` for a wrong type. Wrong argument count: `wrong number of arguments to NAME`.
  Unknown function: `no such function: NAME` (NAME upper-case).
- Aggregates `COUNT(*)`, `COUNT(x)`, `SUM(x)`, `MIN(x)`, `MAX(x)`, each with optional `DISTINCT` (exactly one argument,
  else `wrong number of arguments to NAME`). They ignore NULLs. `COUNT` of nothing is 0; `SUM`/`MIN`/`MAX` of nothing are
  NULL. `SUM` needs INT (`type error`); MIN/MAX work on INT or TEXT (mixed types: `type error`). `COUNT(*)` counts rows.
  DISTINCT removes duplicate non-NULL values first.

## Execution of SELECT

1. Each table in FROM/JOIN must exist (`no such table: NAME`, checked left to right). Aliases default to the table
   name; a repeated alias is `duplicate alias: NAME`. A column is visible as `col` or `alias.col`.
2. Name resolution happens before any row is read, in this order: each JOIN condition, the stars, GROUP BY columns,
   WHERE, the select items left to right, HAVING, ORDER BY items left to right. An unqualified column that exists in
   more than one table is `ambiguous column: NAME`; an unknown one is `no such column: NAME` (for `t.c`:
   `no such column: t.c`); `t.*` for an unknown alias is `no such table: t`. Unknown functions and wrong argument
   counts are also reported in this pass. Aggregates are not allowed in WHERE, JOIN conditions, GROUP BY or
   inside another aggregate: `misuse of aggregate`.
3. Rows: the first table's rows in insertion order. Each JOIN, in order, builds new rows by looping over the
   current rows (outer, in order) and the joined table's rows (inner, insertion order), keeping the combinations
   whose ON condition is true. For `LEFT JOIN`, an outer row with no match is kept once with NULLs for the joined
   table's columns. Without FROM there is exactly one row with no columns.
4. WHERE filters rows.
5. The query is *aggregated* if it has a GROUP BY or HAVING, or any aggregate in the select items or ORDER BY.
   Aggregated queries form groups: with GROUP BY, rows are grouped by the values of the GROUP BY columns (NULLs are
   equal to each other) and groups appear in order of their first row; with no GROUP BY there is exactly one group
   (even when no rows remain, in which case aggregates see zero rows). In an aggregated query, every column reference
   outside an aggregate (select items, HAVING, ORDER BY) must be one of the GROUP BY columns, else
   `column NAME must appear in GROUP BY`. HAVING is evaluated per group and keeps true groups.
6. The select list is evaluated per row (or per group). `*` expands to all columns of all tables in FROM order;
   `t.*` to one table's columns. Result column names: the alias if given, else the column name for a plain column
   reference (qualifier dropped, including star expansions), else `?column?`.
7. ORDER BY items: an integer literal N means output column N (error `bad ORDER BY position` if out of `1..count`);
   an unqualified name equal to an output column name (alias or column name; the first such output column) means
   that output column; anything else is an expression evaluated like a select item. Sorting is stable; keys compare
   NULL < INT < TEXT, INT numerically, TEXT bytewise; `DESC` reverses a key.
8. `DISTINCT` removes later duplicate output rows (NULLs equal) before ordering. Then `OFFSET` skips rows and `LIMIT`
   keeps at most N.

Runtime errors (`type error`, `division by zero`) arise while evaluating rows in the order above and only if some row
is actually evaluated.

### SELECT output

First line: the column names joined by `|`. Then one line per row with values joined by `|`: INT in decimal, TEXT as is
(no quotes or escaping), NULL as `NULL`, booleans as `true`/`false`. Last line: `(N rows)` (always `rows`, even
for 1).

## Other statements

- `CREATE TABLE` prints `ok`. Errors: `table NAME already exists`, `duplicate column: NAME`, `multiple primary keys`
  (more than one PRIMARY KEY column). `PRIMARY KEY` implies NOT NULL and unique.
- `DROP TABLE` prints `ok`; missing table: `no such table: NAME`.
- `INSERT` prints `inserted N`. The table must exist; listed columns are resolved in order (`no such column: NAME`,
  `duplicate column: NAME`); unlisted columns become NULL; without a column list all columns in order. Rows are
  processed in order: first `wrong number of values` if the count differs, then the value expressions are resolved
  and evaluated left to right (they cannot reference columns: `no such column: NAME`; aggregates are
  `misuse of aggregate`), then the row's constraints are checked in column declaration order: for each column a NULL
  in a NOT NULL/PRIMARY KEY column is `NOT NULL constraint failed: COL` and a value of the wrong type
  (INT column needs INT, TEXT column needs TEXT) is `type mismatch in column COL`. After all rows are built, a duplicate
  PRIMARY KEY value (within the new rows or against existing rows) is `duplicate primary key: V` (V is the value as
  printed). Any error means no row of the statement is inserted.
- `UPDATE` prints `updated N` (number of rows matching WHERE; all rows without WHERE). Checks in order: table
  (`no such table`), assigned column names left to right (`no such column`), expressions left to right, WHERE.
  Then for each row in order: evaluate WHERE; if true evaluate all assignments against the **old** row values, then
  apply the same per-row constraint checks as INSERT. After all rows, duplicate primary keys in the table are
  `duplicate primary key: V`. Any error leaves the table unchanged. Aggregates in SET/WHERE: `misuse of aggregate`.
- `DELETE` prints `deleted N`. Table check, WHERE resolution, then rows evaluated in order.

## Example

Input:

    CREATE TABLE t (a INT PRIMARY KEY, b TEXT);
    INSERT INTO t VALUES (1, 'x'), (2, NULL);
    SELECT b, a + 1 AS n FROM t ORDER BY a DESC;
    INSERT INTO t VALUES (1, 'y');
    SELECT c FROM t;

Output:

    ok
    inserted 2
    b|n
    NULL|3
    x|2
    (2 rows)
    error: duplicate primary key: 1
    error: no such column: c
