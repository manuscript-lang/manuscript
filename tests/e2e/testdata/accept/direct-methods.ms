import panic from "@std/faults.ms"

type Counter:
    n: Int

type Shape:
    case Circle(r: Int)
    case Square(side: Int)

interface Bumper:
    fn bump(by: Int) Int

interface Scaler:
    fn scale(factor: Int, offset: Optional[Int] = none) Int

impl Bumper for Counter:
    fn bump(by: Int) Int: self.n + by

impl Scaler for Counter:
    fn scale(factor: Int, offset: Optional[Int] = none) Int: (
        self.n * factor
        + offset.get(0)
    )

impl Bumper for Shape:
    fn bump(by: Int) Int:
        match self:
            Circle(r): return r + by
            Square(side): return side * by

fn through_view(b: Bumper, by: Int) Int:
    return b.bump(by)

fn guarded(c: Counter, by: Int) Int:
    if by < 0:
        return 0

    return c.bump(by)

test "method calls on concrete receivers":
    let c = Counter(4)
    if not (c.bump(3) == 7):
        return panic("record")
    if not (Shape.Circle(2).bump(1) == 3):
        return panic("circle")
    if not (Shape.Square(3).bump(2) == 6):
        return panic("square")

test "one call site sees different receiver types":
    let counters: List[Counter] = [Counter(1), Counter(2), Counter(3)]
    var total = 0
    for counter in counters:
        total += guarded(counter, 10)
    if not (total == 36):
        return panic("loop")

test "views, defaults, and reordered labels keep dispatch":
    let c = Counter(5)
    if not (through_view(Bumper(c), 2) == 7):
        return panic("view")
    if not (c.scale(2) == 10):
        return panic("default")
    if not (c.scale(offset: some(1), factor: 2) == 11):
        return panic("reordered")
    if not (c.scale(2, some(3)) == 13):
        return panic("ordered")

type Parser:
    base: Int

interface Parse:
    fn parse(n: Int) Result[Int, String]

impl Parse for Parser:
    fn parse(n: Int) Result[Int, String]:
        if n < 0:
            return error("negative")

        return ok(self.base + n)

type Chain:
    parser: Parser

interface Step:
    fn step(n: Int) Result[Int, String]

impl Step for Chain:
    fn step(n: Int) Result[Int, String]:
        return ok((try self.parser.parse(n)) + 1)

fn code(r: Result[Int, String]) Int:
    return r.get(-1)

fn run_direct(chain: Chain, n: Int) Int:
    return chain.step(n) | code

fn run_view(chain: Chain, n: Int) Int:
    return Step(chain).step(n) | code

fn run_bound(chain: Chain, n: Int) Int:
    let callback = chain.step
    return callback(n) | code

test "nested try in a direct method becomes an error result":
    let chain = Chain(Parser(10))
    if not (run_direct(chain, 5) == 16):
        return panic("ok")
    if not (run_direct(chain, -5) == -1):
        return panic("direct error result")
    if not (run_view(chain, -5) == -1):
        return panic("view error result")
    if not (run_bound(chain, -5) == -1):
        return panic("bound error result")
    if not (run_bound(chain, 5) == 16):
        return panic("bound ok")
