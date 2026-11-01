import expect_equal from "@std/test/test.ms"

interface Visitor[R]:
    fn visit(n: Int) R

type Doubler:
    k: Int

impl Visitor[Int] for Doubler:
    fn visit(n: Int) Int:
        return n * self.k

impl Visitor[String] for Doubler:
    fn visit(n: Int) String:
        return "<{n}>"

fn run[R](v: Visitor[R], n: Int) R:
    return v.visit(n)

test "one receiver implements two applications of a generic contract":
    let d = Doubler(k: 3)
    let as_int: Visitor[Int] = d
    let as_string: Visitor[String] = d
    let a: Int = run(as_int, 5)
    let b: String = run(as_string, 5)
    try expect_equal(a, 15)
    try expect_equal(b, "<5>")
