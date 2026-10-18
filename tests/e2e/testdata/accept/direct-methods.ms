import {expect_equal} from "@std/testing.ms"

type Counter:
    n: Int

type Shape:
    case Circle(r: Int)
    case Square(side: Int)

interface Bumper:
    fn bump(by: Int) -> Int

interface Scaler:
    fn scale(factor: Int, offset: Optional[Int] = none) -> Int

impl Bumper for Counter:
    fn bump(by: Int) -> Int: self.n + by

impl Scaler for Counter:
    fn scale(factor: Int, offset: Optional[Int] = none) -> Int: (
        self.n * factor
        + offset.unwrap_or(fallback: 0)
    )

impl Bumper for Shape:
    fn bump(by: Int) -> Int:
        match self:
            Circle(r): return r + by
            Square(side): return side * by

fn through_view(b: Bumper, by: Int) -> Int:
    return b.bump(by: by)

fn guarded(c: Counter, by: Int) -> Int:
    if by < 0:
        return 0

    return c.bump(by: by)

test "method calls on concrete receivers":
    let c = Counter(n: 4)
    c.bump(by: 3) | try expect_equal(expected: 7)
    Shape.Circle(r: 2).bump(by: 1) | try expect_equal(expected: 3)
    Shape.Square(side: 3).bump(by: 2) | try expect_equal(expected: 6)

test "one call site sees different receiver types":
    let counters: List[Counter] = [Counter(n: 1), Counter(n: 2), Counter(n: 3)]
    var total = 0
    for counter in counters:
        total = total + guarded(c: counter, by: 10)
    total | try expect_equal(expected: 36)

test "views, defaults, and reordered labels keep dispatch":
    let c = Counter(n: 5)
    through_view(b: Bumper(value: c), by: 2) | try expect_equal(expected: 7)
    c.scale(factor: 2) | try expect_equal(expected: 10)
    c.scale(offset: some(1), factor: 2) | try expect_equal(expected: 11)
    c.scale(factor: 2, offset: some(3)) | try expect_equal(expected: 13)

type Parser:
    base: Int

interface Parse:
    fn parse(n: Int) -> Result[Int, String]

impl Parse for Parser:
    fn parse(n: Int) -> Result[Int, String]:
        if n < 0:
            return error("negative")

        return ok(self.base + n)

type Chain:
    parser: Parser

interface Step:
    fn step(n: Int) -> Result[Int, String]

impl Step for Chain:
    fn step(n: Int) -> Result[Int, String]:
        return ok((try self.parser.parse(n: n)) + 1)

fn code(r: Result[Int, String]) -> Int:
    match r:
        ok(value): return value
        error(_): return -1

fn run_direct(chain: Chain, n: Int) -> Int:
    return code(r: chain.step(n: n))

fn run_view(chain: Chain, n: Int) -> Int:
    return code(r: Step(value: chain).step(n: n))

fn run_bound(chain: Chain, n: Int) -> Int:
    let callback = chain.step
    return code(r: callback(n: n))

test "nested try in a direct method becomes an error result":
    let chain = Chain(parser: Parser(base: 10))
    run_direct(chain: chain, n: 5) | try expect_equal(expected: 16)
    run_direct(chain: chain, n: -5) | try expect_equal(expected: -1)
    run_view(chain: chain, n: -5) | try expect_equal(expected: -1)
    run_bound(chain: chain, n: -5) | try expect_equal(expected: -1)
    run_bound(chain: chain, n: 5) | try expect_equal(expected: 16)
