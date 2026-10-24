from "@std/testing.ms" import expect_equal

interface Visitor[R]:
    def visit(n: Int) -> R

type Doubler:
    k: Int

impl Visitor[Int] for Doubler:
    def visit(n: Int) -> Int:
        return n * self.k

impl Visitor[String] for Doubler:
    def visit(n: Int) -> String:
        return f"<{n}>"

def run[R](v: Visitor[R], n: Int) -> R:
    return v.visit(n)

test "one receiver implements two applications of a generic contract":
    let d = Doubler(k: 3)
    let a: Int = run(Visitor[Int](value: d), 5)
    let b: String = run(Visitor[String](value: d), 5)
    try expect_equal(a, 15)
    try expect_equal(b, "<5>")
