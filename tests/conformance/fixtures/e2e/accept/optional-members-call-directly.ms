# conform: tags=closures,faults,lists,modules,optional,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/optional-members-call-directly.ms
from "@std/testing.ms" import expect_equal, expect_true

def fallback() -> Int: 9

test "optional members":
    let present = some(3)
    let absent: Optional[Int] = none
    try expect_true((present.is_some() and not present.is_none()))
    try expect_true((absent.is_none() and not absent.is_some()))
    try expect_true((present.get(default: 7) == 3))
    try expect_true((absent.get(default: 7) == 7))
    try expect_true(
        (
            absent.or_else(
                create: lambda () -> Optional[Int]: some(fallback())
            ).get() == 9
        )
    )
    try expect_true((present.map(lambda (value: Int) -> Int: value + 1).get() == 4))

    var items = List[Int]()
    try expect_equal(items.get(index: 0, default: -1), -1)
    items.append(value: 5)
    try expect_true(
        (
            items.get(index: 0, default: -1) == 5
            and items.first().get(default: 0) == 5
        )
    )
