import panic from "@std/faults.ms"

import List from "@std/collections.ms"

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
    if not (c.bump(by: 3) == 7):
        return panic(message: "record")
    if not (Shape.Circle(r: 2).bump(by: 1) == 3):
        return panic(message: "circle")
    if not (Shape.Square(side: 3).bump(by: 2) == 6):
        return panic(message: "square")

test "one call site sees different receiver types":
    let counters: List[Counter] = [Counter(n: 1), Counter(n: 2), Counter(n: 3)]
    var total = 0

    for counter in counters:
        total = total + guarded(c: counter, by: 10)

    if not (total == 36):
        return panic(message: "loop")

test "views, defaults, and reordered labels keep dispatch":
    let c = Counter(n: 5)
    if not (
        through_view(
            b: Bumper(value: c),
            by: 2
        ) == 7
    ):
        return panic(message: "view")
    if not (c.scale(factor: 2) == 10):
        return panic(message: "default")
    if not (
        c.scale(
            offset: some(1),
            factor: 2
        ) == 11
    ):
        return panic(message: "reordered")
    if not (
        c.scale(
            factor: 2,
            offset: some(3)
        ) == 13
    ):
        return panic(message: "ordered")
