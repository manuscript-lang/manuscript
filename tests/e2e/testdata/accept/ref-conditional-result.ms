from "@std/test.ms" import expect_equal

type Pair:
    left: String
    right: String
    items: List[String]

impl Pair:
    def pick(first: Bool) -> ref String: self.left if first else self.right

    def deep(n: Int) -> ref String: self.left if n == 0 else (
        self.right if n == 1 else self.items[0]
    )

test "a lending function can return either branch of a conditional":
    let pair = Pair("l".repeat(20).get(), "rr".repeat(10).get(), ["i".repeat(5).get()])
    pair.pick(True).length() | try expect_equal(20)
    pair.pick(False).length() | try expect_equal(20)
    pair.deep(0).length() | try expect_equal(20)
    pair.deep(1).length() | try expect_equal(20)
    pair.deep(2).length() | try expect_equal(5)
