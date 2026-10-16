import {
    expect_true,
    expect_false,
    expect_equal,
    expect_not_equal,
    expect_close,
    expect_contains,
    expect_some,
    expect_none,
    expect_ok,
    expect_error,
    expect_fault,
    fail,
    assert_equal
} from "@std/testing.ms"

fn identity[T](value: T) -> T:
    return value

test "testing assertions":
    expect_true(true)
    expect_false(false)
    expect_equal(identity(3), 3)
    assert_equal("hello", "hello")
    expect_equal([1, 2], [1, 2])
    expect_not_equal(1, 2)
    expect_close(1.01, 1.0, 0.02)
    expect_contains("Manuscript", "script")
    let present: Optional[Int] = some(7)
    let absent: Optional[Int] = none
    expect_equal(expect_some(present), 7)
    expect_none(absent)
    let success: Result[Int, String] = ok(9)
    let failure: Result[Int, String] = error("bad")
    expect_equal(expect_ok(success), 9)
    expect_equal(expect_error(failure), "bad")
    expect_contains(expect_fault(fn(): expect_equal(1, 2)), "expected 2, got 1")
    expect_contains(
        expect_fault(
            fn():
                let message = expect_fault(fn(): expect_true(true))
        ),
        "returned normally"
    )

type Key:
    id: Int
    label: String

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

test "assertions preserve domain equality":
    expect_equal(Key(id: 1, label: "first"), Key(id: 1, label: "second"))
    expect_not_equal(Key(id: 1, label: "first"), Key(id: 2, label: "first"))
