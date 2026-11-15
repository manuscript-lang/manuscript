# SQL engine: CASE expressions

The program in this directory is a working in-memory SQL database (it reads a script of SQL statements from stdin and prints each statement's result). Add searched `CASE` expressions. Everything it does today must stay exactly as it is, including every error message and the order in which things are checked.

## Syntax

```
case := CASE WHEN expr THEN expr (WHEN expr THEN expr)* [ELSE expr] END
```

A `CASE` expression is an expression and can appear anywhere an expression can (select items, `WHERE`, `HAVING`, `ORDER BY`, `GROUP BY`, `UPDATE ... SET`, `INSERT ... VALUES`, function arguments, aggregate arguments, other `CASE` expressions). The words `CASE`, `WHEN`, `THEN`, `ELSE` and `END` become reserved keywords (case-insensitive like the other keywords): they can no longer be table, column or alias names. At least one `WHEN` is required; `CASE` without it, a missing `THEN` or a missing `END` is `error: syntax error` (checked before anything else, like every syntax error). There is no simple form (`CASE expr WHEN value ...`): the word after `CASE` must be `WHEN`.

## Meaning

The `WHEN` conditions are evaluated in order, left to right. The first condition that is true selects its `THEN` expression, whose value is the value of the `CASE`; no other `THEN`, later `WHEN` or `ELSE` expression is evaluated (so an error in them does not occur). A NULL condition counts as false. A condition that is neither a boolean nor NULL is `error: type error` (as in `WHERE`). If no condition is true, the value is the `ELSE` expression, or NULL when there is none. The result expressions may have different types (a `CASE` can give an INT in one row and a TEXT in another).

A `CASE` is not a plain column: an unaliased `CASE` select item is named `?column?`, like other expressions. In an aggregate query a `CASE` outside an aggregate call may only use grouped columns and aggregates, by the same rules as any other expression, and a `CASE` inside an aggregate call is evaluated once per row of the group.

Everything else is unchanged.
