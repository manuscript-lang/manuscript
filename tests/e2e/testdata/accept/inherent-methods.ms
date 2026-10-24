from "@std/core.ms" import panic

interface Show:
    def show() -> String

type Counter:
    value: Int

type Box[T]:
    item: T

type Shape:
    case Circle(r: Int)
    case Square(s: Int)

impl Counter:
    def double() -> Int:
        return self.value * 2

    def bump(by: Int = 1) -> Counter:
        return Counter(value: self.value + by)

    def depth(n: Int) -> Int:
        if n == 0:
            return self.value

        return self.depth(n: n - 1) + 1

impl Counter:
    def overflow() -> Int:
        return self.value * self.value

impl Show for Counter:
    def show() -> String:
        return "counter"

impl Box[T]:
    def get() -> ref T:
        return self.item

impl Shape:
    def area() -> Int:
        match self:
            case Circle(r): return r * r * 3
            case Square(s): return s * s

def check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "inherent methods":
    let counter = Counter(value: 4)
    check(ok: counter.double() == 8, name: "double")
    check(ok: counter.bump().value == 5, name: "default argument")
    check(ok: counter.bump(by: 3).value == 7, name: "explicit argument")
    check(ok: counter.depth(n: 5) == 9, name: "recursion")
    check(ok: counter.show() == "counter", name: "contract beside inherent")
    check(ok: Box(item: 7).get() == 7, name: "generic receiver")
    check(ok: Shape.Square(s: 3).area() == 9, name: "alternative receiver")
    check(ok: Circle(r: 2).area() == 12, name: "unqualified case")
