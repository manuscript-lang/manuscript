import panic from "@std/core.ms"

interface Show:
    fn show() String

type Counter:
    value: Int

type Box[T: Clonable]:
    item: T

type Shape:
    case Circle(r: Int)
    case Square(s: Int)

impl Counter:
    fn double() Int:
        return self.value * 2

    fn bump(by: Int = 1) Counter:
        return Counter(value: self.value + by)

    fn depth(n: Int) Int:
        if n == 0:
            return self.value

        return self.depth(n: n - 1) + 1

impl Counter:
    fn overflow() Int:
        return self.value * self.value

impl Show for Counter:
    fn show() String:
        return "counter"

impl Box[T]:
    fn get() T:
        return self.item.clone()

impl Shape:
    fn area() Int:
        match self:
            Circle(r): return r * r * 3
            Square(s): return s * s

fn check(ok: Bool, name: String) Unit:
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
