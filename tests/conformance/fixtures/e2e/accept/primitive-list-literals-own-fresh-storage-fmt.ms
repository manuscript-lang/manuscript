// conform: tags=faults,formatter,lists,modules,parser,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/primitive-list-literals-own-fresh-storage.ms
import expect_true from "@std/test/test.ms"

fn fresh() List[Int]:
    return [1, 2, 3]

test "literals":
    var a = fresh()
    b := fresh()
    a.append(value: 4)
    try expect_true((a.length() == 4 and b.length() == 3))

    var floats = [1.5, 2.5]
    flags := [true, false, true]
    var words = ["a", "b"]
    empty := List[Int]()
    try expect_true(
        (
            floats.length() == 2
            and flags.length() == 3
            and words.length() == 2
            and empty.is_empty()
        )
    )
    floats.append(value: 3.5)
    words.append(value: "c")
    try expect_true((floats.get(index: 2) == 3.5 and words.get(index: 2) == "c"))
    try expect_true(([1, 2] == [1, 2] and not ([1, 2] == [2, 1])))

    rows := [[1], [2, 3]]
    try expect_true((rows.get(index: 1) == [2, 3]))
