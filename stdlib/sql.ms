# Typed SQL statement builders. A statement is assembled from validated identifiers, typed values and
# conditions; there is no entry point that accepts raw SQL text, so a value can never become syntax.
# Every value travels as a bound parameter (`?` in the text), and identifiers are validated, then double-quoted.
# `update` and `delete` require a condition, so a full-table change names `Condition.Always` explicitly.
#
# ```manuscript
# let users = try ident("users")
# let name = try ident("name")
# let statement = try select_from(users, [name], where: Condition.Eq(name, Value.Text("O'Brien")))
# ```
# `statement.text` is `SELECT "name" FROM "users" WHERE "name" = ?` and `statement.params` is `[Value.Text("O'Brien")]`.
from "@std/bytes.ms" import Bytes

# Why a statement could not be built.
export type SqlError:
    # An identifier is empty, longer than 63 bytes, or not made of ASCII letters, digits and underscores starting with a letter or underscore.
    case InvalidIdentifier(
        # The rejected identifier text.
        name: String
    )
    # A select lists no columns, an insert or update sets none, or an `In` condition lists no values.
    case EmptyList
    # `limit` is negative; the limit must be zero or more.
    case InvalidLimit

impl Error for SqlError:
    # Returns `sql: invalid identifier <name>`, `sql: empty list` or `sql: invalid limit`.
    def message() -> String:
        match self:
            case InvalidIdentifier(name): return f"sql: invalid identifier {name}"
            case EmptyList: return "sql: empty list"
            case InvalidLimit: return "sql: invalid limit"

# A validated table or column name. Build one with `ident`.
export type Ident:
    # The validated name, unquoted.
    name: String

# A value bound to a statement as a parameter.
export type Value:
    # SQL NULL, bound as an absent value; compare with `IsNull`, since `= NULL` never matches.
    case Null
    # A 64-bit integer.
    case Integer(
        # The integer bound to the placeholder.
        value: Int
    )
    # A floating-point number.
    case Real(
        # The floating-point number bound to the placeholder.
        value: Float
    )
    # Text, bound as a string.
    case Text(
        # The text bound to the placeholder; quotes and SQL keywords in it stay data.
        value: String
    )
    # A boolean, bound as a parameter.
    case Flag(
        # The boolean bound to the placeholder.
        value: Bool
    )
    # Binary data, bound as a blob parameter.
    case Blob(
        # The bytes bound to the placeholder.
        value: Bytes
    )

# A column and the value written to it by `insert` or `update`.
export type Assignment:
    # The quoted column that receives the value in the statement.
    column: Ident
    # The value stored, bound as a parameter.
    value: Value

# A row filter. Comparisons bind their value as a parameter.
export type Condition:
    # Matches every row; the explicit form of "no filter".
    case Always
    # The column equals the value.
    case Eq(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column differs from the value.
    case Ne(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column is less than the value.
    case Lt(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column is less than or equal to the value.
    case Le(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column is greater than the value.
    case Gt(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column is greater than or equal to the value.
    case Ge(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The value compared against the column, bound as a parameter.
        value: Value
    )
    # The column matches a LIKE pattern, where `%` and `_` are wildcards in the bound text.
    case Like(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The LIKE pattern, bound as text; `%` matches any run and `_` any one character.
        pattern: String
    )
    # The column equals one of the values; an empty list is `EmptyList`.
    case In(
        # The quoted column whose value is compared in the WHERE clause.
        column: Ident,
        # The accepted values, each bound as a parameter; must not be empty.
        values: List[Value]
    )
    # The column is NULL.
    case IsNull(
        # The quoted column that must hold NULL for the row to match.
        column: Ident
    )
    # Matches rows where both conditions hold, rendered as a parenthesized AND.
    case And(
        # The first operand, rendered before the operator and evaluated first.
        left: Condition,
        # The second operand, rendered after the operator in the same parenthesized group.
        right: Condition
    )
    # Matches rows where either condition holds, rendered as a parenthesized OR.
    case Or(
        # The first operand, rendered before the operator and evaluated first.
        left: Condition,
        # The second operand, rendered after the operator in the same parenthesized group.
        right: Condition
    )
    # The condition does not hold.
    case Not(
        # The condition whose result is inverted by NOT.
        inner: Condition
    )

# One ORDER BY term.
export type Order:
    # The column ordered by.
    column: Ident
    # True for descending order.
    descending: Bool = False

# A finished statement: text with `?` placeholders and the values bound to them in order.
export type Statement:
    # SQL text containing only validated, quoted identifiers and `?` placeholders.
    text: String
    # Parameter values in placeholder order.
    params: List[Value]

type Fragment:
    text: String
    params: List[Value]

# Validates `name` as a table or column name: 1 to 63 ASCII letters, digits or underscores, not starting with a digit.
export def ident(name: String) -> Result[Ident, SqlError]:
    let scalars = name.scalar_values()
    if scalars.is_empty() or scalars.length() > 63: return error(
        SqlError.InvalidIdentifier(name)
    )
    if not name_start(scalars[0]): return error(SqlError.InvalidIdentifier(name))

    for scalar in scalars:
        if not name_start(scalar) and not (scalar >= 48 and scalar <= 57): return error(
            SqlError.InvalidIdentifier(name)
        )
    return ok(Ident(name))

# Builds `SELECT <columns> FROM <table> [WHERE ...] [ORDER BY ...] [LIMIT n]`.
export def select_from(
    table: Ident,
    columns: List[Ident],
    where: Condition = Condition.Always,
    order_by: List[Order] = [],
    limit: Optional[Int] = none
) -> Result[Statement, SqlError]:
    if columns.is_empty(): return error(SqlError.EmptyList)

    let filter = try render(where.clone())
    var text = f"SELECT {quote_all(columns)} FROM {quote(table)}"
    if where_needed(where.clone()): text = f"{text} WHERE {filter.text}"

    if not order_by.is_empty():
        let terms = order_by.map(
            lambda o: (
                quote(o.column.clone())
                + (" DESC" if o.descending else " ASC")
            )
        )
        text = f"{text} ORDER BY {terms.join(", ")}"

    if let count = limit:
        if count < 0: return error(SqlError.InvalidLimit)

        text = f"{text} LIMIT {count}"

    return ok(Statement(text, filter.params.clone()))

# Builds `INSERT INTO <table> (<columns>) VALUES (?, ...)`.
export def insert_into(
    table: Ident,
    values: List[Assignment]
) -> Result[Statement, SqlError]:
    if values.is_empty(): return error(SqlError.EmptyList)

    let columns = quote_all(values.map(lambda a: a.column.clone()))
    let marks = values.map(lambda a: "?").join(", ")
    let params = values.map(lambda a: a.value.clone())
    return ok(
        Statement(
            f"INSERT INTO {quote(table)} ({columns}) VALUES ({marks})", params
        )
    )

# Builds `UPDATE <table> SET <column> = ?, ... WHERE ...`. The condition is required; pass `Condition.Always` to change every row.
export def update_table(
    table: Ident,
    values: List[Assignment],
    where: Condition
) -> Result[Statement, SqlError]:
    if values.is_empty(): return error(SqlError.EmptyList)

    let filter = try render(where.clone())
    let sets = values.map(lambda a: quote(a.column.clone()) + " = ?").join(", ")
    var text = f"UPDATE {quote(table)} SET {sets}"
    if where_needed(where.clone()): text = f"{text} WHERE {filter.text}"

    let params = values.map(lambda a: a.value.clone()).concat(filter.params.clone())
    return ok(Statement(text, params))

# Builds `DELETE FROM <table> WHERE ...`. The condition is required; pass `Condition.Always` to delete every row.
export def delete_from(table: Ident, where: Condition) -> Result[Statement, SqlError]:
    let filter = try render(where.clone())
    var text = f"DELETE FROM {quote(table)}"
    if where_needed(where.clone()): text = f"{text} WHERE {filter.text}"
    return ok(Statement(text, filter.params.clone()))

def name_start(scalar: Int) -> Bool:
    return (
        (scalar >= 65 and scalar <= 90)
        or (scalar >= 97 and scalar <= 122)
        or scalar == 95
    )

def quote(name: Ident) -> String: f"\"{name.name}\""

def quote_all(names: List[Ident]) -> String:
    return names.map(lambda n: quote(n)).join(", ")

def where_needed(condition: Condition) -> Bool:
    match condition:
        case Always: return False
        case _: return True

def compare(column: Ident, operator: String, value: Value) -> Result[Fragment, SqlError]:
    return ok(Fragment(f"{quote(column)} {operator} ?", [value]))

def join_pair(
    left: Condition,
    word: String,
    right: Condition
) -> Result[Fragment, SqlError]:
    let first = try render(left)
    let second = try render(right)
    return ok(
        Fragment(
            f"({first.text} {word} {second.text})", first.params.concat(second.params)
        )
    )

def render(condition: Condition) -> Result[Fragment, SqlError]:
    match condition:
        case Always: return ok(Fragment("1 = 1", []))
        case Eq(column, value): return compare(column, "=", value)
        case Ne(column, value): return compare(column, "<>", value)
        case Lt(column, value): return compare(column, "<", value)
        case Le(column, value): return compare(column, "<=", value)
        case Gt(column, value): return compare(column, ">", value)
        case Ge(column, value): return compare(column, ">=", value)
        case Like(column, pattern): return compare(column, "LIKE", Value.Text(pattern))
        case In(column, values): return render_in(column, values)
        case IsNull(column): return ok(Fragment(f"{quote(column)} IS NULL", []))
        case And(left, right): return join_pair(left, "AND", right)
        case Or(left, right): return join_pair(left, "OR", right)
        case Not(inner): return render_not(inner)

def render_in(column: Ident, values: List[Value]) -> Result[Fragment, SqlError]:
    if values.is_empty(): return error(SqlError.EmptyList)

    let marks = values.map(lambda v: "?").join(", ")
    return ok(Fragment(f"{quote(column)} IN ({marks})", values.clone()))

def render_not(inner: Condition) -> Result[Fragment, SqlError]:
    let rendered = try render(inner)
    return ok(Fragment(f"(NOT {rendered.text})", rendered.params.clone()))
