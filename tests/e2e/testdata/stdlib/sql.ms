from "@std/sql.ms" import ident, select_from, insert_into, update_table, delete_from, Condition, Value, Assignment, Order, SqlError, Statement, Ident
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal, expect_ok, fail

def failure(result: Result[Statement, SqlError]) -> Result[SqlError, Error]:
    match result:
        case ok(_): return error(TextError("accepted"))
        case error(cause): return ok(cause)

test "sql select binds values and never splices them into the text":
    let users = try ident("users")
    let name = try ident("name")
    let age = try ident("age")
    let hostile = "x'; DROP TABLE users; --"
    let filter = Condition.And(
        Condition.Eq(name.clone(), Value.Text(hostile.clone())),
        Condition.Gt(age.clone(), Value.Integer(3))
    )
    let statement = try select_from(
        users, [name.clone()], where: filter, order_by: [Order(age.clone(), True)],
        limit: some(5)
    )
    try expect_equal(
        statement.text,
        "SELECT \"name\" FROM \"users\" WHERE (\"name\" = ? AND \"age\" > ?) ORDER BY \"age\" DESC LIMIT 5"
    )
    try expect_equal(statement.params, [Value.Text(hostile), Value.Integer(3)])

test "sql rejects identifiers that could carry syntax":
    for bad in ["", "1a", "a b", "a;b", "a\"b", "users--", "a.b"]:
        let result = ident(bad.clone())
        if result.is_ok(): return error(TextError(f"accepted {bad}"))

    let good = try ident("_ok_1")
    try expect_equal(good.name, "_ok_1")

test "sql insert update and delete bind every value":
    let users = try ident("users")
    let name = try ident("name")
    let id = try ident("id")
    let add = try insert_into(
        users.clone(), [Assignment(name.clone(), Value.Text("a"))]
    )
    try expect_equal(add.text, "INSERT INTO \"users\" (\"name\") VALUES (?)")

    let change = try update_table(
        users.clone(), [Assignment(name.clone(), Value.Null)],
        Condition.Eq(id.clone(), Value.Integer(7))
    )
    try expect_equal(change.text, "UPDATE \"users\" SET \"name\" = ? WHERE \"id\" = ?")
    try expect_equal(change.params, [Value.Null, Value.Integer(7)])

    let drop = try delete_from(users.clone(), Condition.Always)
    try expect_equal(drop.text, "DELETE FROM \"users\"")

test "sql refuses empty lists and negative limits":
    let users = try ident("users")
    let name = try ident("name")
    let empty = try failure(select_from(users.clone(), List[Ident]()))
    try expect_equal(empty, SqlError.EmptyList)

    let none_in = try failure(
        delete_from(users.clone(), Condition.In(name.clone(), List[Value]()))
    )
    try expect_equal(none_in, SqlError.EmptyList)

    let limit = try failure(select_from(users.clone(), [name.clone()], limit: some(-1)))
    try expect_equal(limit, SqlError.InvalidLimit)
