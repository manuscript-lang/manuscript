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
    let as_int: Visitor[Int] = d
    let as_string: Visitor[String] = d
    let a: Int = run(as_int, 5)
    let b: String = run(as_string, 5)
    try expect_equal(a, 15)
    try expect_equal(b, "<5>")
