from "@std/ids.ms" import Id, IdError, id_from
from "@std/core.ms" import TextError
from "@std/testing.ms" import expect_equal

type User:
    name: String

type Order:
    total: Int

def user_text(id: Id[User]) -> String: id.value.clone()

test "ids of different types are separate but share text rules":
    let user = try id_from[User]("u-42")
    try expect_equal(user_text(user), "u-42")

    let order = try id_from[Order]("u-42")
    try expect_equal(order.value, "u-42")

test "ids reject empty and control text":
    for bad in ["", "a\nb", "a\u{0}b"]:
        let result = id_from[User](bad.clone())
        if result.is_ok(): return error(TextError(f"accepted {bad}"))

test "ids are map keys":
    var owners = Map[Id[User], Int]()
    owners.add(Id[User]("a"), 1)
    try expect_equal(owners.get_or(Id[User]("a"), 0), 1)
