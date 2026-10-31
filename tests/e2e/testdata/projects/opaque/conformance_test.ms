import expect_equal, expect_true, expect_false from "@std/test.ms"
import Approved, Counter, Mode, approve, entity, nonce_of, counter, safe, wild, level from "./gate.ms"

fn show[T](value: T) String:
    return "{value}"

test "module functions and methods work on an opaque value":
    let a = approve("u1")
    entity(a) | try expect_equal("u1")
    nonce_of(a) | try expect_equal("n1")
    a.label() | try expect_equal("approved:u1")

test "a mutating method changes an opaque value":
    var c = counter()
    c.bump()
    c.bump()
    c.value() | try expect_equal(2)

test "an opaque value copies, clones and compares":
    let a = approve("u1")
    let b = a.clone()
    try expect_true(a == b)
    try expect_false(a == approve("u2"))
    entity(b) | try expect_equal("u1")

test "an opaque value prints only its type name":
    let a = approve("u1")
    "{a}" | try expect_equal("Approved")
    a.to_string() | try expect_equal("Approved")
    show(a) | try expect_equal("Approved")
    show([a, approve("u2")]) | try expect_equal("[Approved, Approved]")
    show(counter()) | try expect_equal("Counter")
    show(safe()) | try expect_equal("Mode")
    show(wild(7)) | try expect_equal("Mode")

test "an opaque value lives in collections and optionals":
    var all = List[Approved]()
    all.append(approve("u1"))
    all.append(approve("u2"))
    all.length() | try expect_equal(2)
    entity(all[1]) | try expect_equal("u2")

    let maybe: Approved? = approve("u3")

    if let found = maybe:
        entity(found) | try expect_equal("u3")
    else:
        try expect_true(false)

test "an opaque alternative is built and read through the module":
    level(safe()) | try expect_equal(0)
    level(wild(4)) | try expect_equal(4)
