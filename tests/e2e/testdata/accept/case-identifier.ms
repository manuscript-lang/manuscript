import expect_equal from "@std/test/test.ms"

type Item:
    case: Int

enum PayloadKeyword:
    case(value: Int)

enum NullaryKeyword:
    case

fn case(value: Int) Int: value + 1

fn present(value: Int?) Int:
    match value:
        case: return case
        none: return 0

test "case is an ordinary identifier in declarations and patterns":
    try expect_equal(case(7), 8)

    let case = 3
    let item = Item(case: case)
    try expect_equal(item.case, 3)

    let value = PayloadKeyword.case(9)

    match value:
        case(number): try expect_equal(number, 9)

    let flag = NullaryKeyword.case

    match flag:
        case: try expect_equal(case, 3)

    try expect_equal(present(7), 7)
    try expect_equal(present(none), 0)
