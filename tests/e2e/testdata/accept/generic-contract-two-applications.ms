import {expect_equal} from "@std/testing.ms"

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
    let a: Int = run(Visitor[Int](value: d), 5)
    let b: String = run(Visitor[String](value: d), 5)
    try expect_equal(a, 15)
    try expect_equal(b, "<5>")
