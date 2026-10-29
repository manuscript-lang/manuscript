import expect_equal from "@std/test.ms"

type Pair:
    left: String
    right: String
    items: List[String]

impl Pair:
    fn pick(first: Bool) ref String: (if first: self.left else: self.right)

    fn deep(n: Int) ref String: (
        if n == 0: self.left else: (if n == 1: self.right else: self.items[0])
    )

test "a lending function can return either branch of a conditional":
    let pair = Pair("l".repeat(20).get(), "rr".repeat(10).get(), ["i".repeat(5).get()])
    pair.pick(true).length() | try expect_equal(20)
    pair.pick(false).length() | try expect_equal(20)
    pair.deep(0).length() | try expect_equal(20)
    pair.deep(1).length() | try expect_equal(20)
    pair.deep(2).length() | try expect_equal(5)
