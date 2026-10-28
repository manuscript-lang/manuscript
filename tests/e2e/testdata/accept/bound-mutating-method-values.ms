import expect_equal from "@std/test.ms"
import StringBuilder from "@std/string.ms"

type Counter:
    n: Int

impl Counter:
    var fn bump(by: Int = 1) Int:
        self.n += by
        return self.n

interface Stepper:
    var fn step() Int

impl Stepper for Counter:
    var fn step() Int:
        self.n += 10
        return self.n

fn drain(var xs: List[Int]) Unit:
    let push = xs.append
    push(7)
    push(8)

fn each(f: fn(Int) Unit) Unit:
    f(100)

test "a method value that changes its receiver borrows the variable":
    var xs = [1, 2, 3]
    let reverse = xs.reverse
    reverse()

    let add = xs.append
    add(9)
    try expect_equal(xs, [3, 2, 1, 9])

    var counter = Counter(n: 0)
    let bump = counter.bump
    bump()
    bump(by: 5)
    try expect_equal(counter.n, 6)

    var names = Map[String, Int]()
    let put = names.add
    put("a", 1)
    try expect_equal(names.keys(), ["a"])

test "the variable is shared through calls and callbacks":
    var xs = [1]
    drain(var xs)
    each(xs.append)
    try expect_equal(xs, [1, 7, 8, 100])

    let pop = xs.pop
    pop()
    try expect_equal(xs, [1, 7, 8])

test "an interface method value shares the underlying value":
    var counter = Counter(n: 0)
    var view: Stepper = counter
    let step = view.step
    step()
    step()
    try expect_equal(view.step(), 30)

test "a builder method value appends to the builder":
    var sb = StringBuilder()
    let append = sb.append
    append("a")
    append("b")
    sb.build() | try expect_equal("ab")
