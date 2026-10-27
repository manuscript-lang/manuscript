# conform: tags=alternatives,control-flow,generics,interfaces,interpolation,match,modules,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/go-name-collisions.ms
from "@std/test.ms" import expect_equal, expect_false

type Spelled:
    x_: Int
    x: Int
    a_b: Int
    aB: Int

interface Methods:
    def foo_bar() -> Int
    def fooBar() -> Int

impl Methods for Spelled:
    def foo_bar() -> Int:
        return self.x_

    def fooBar() -> Int:
        return self.x

def string(value: Int) -> Int:
    return value + 1

def int(value: Int) -> Int:
    return value + 2

def float64(value: Int) -> Int:
    return value + 3

def nil(value: Int) -> Int:
    return value + 4

test "field names that differ only in underscores stay distinct":
    let value = Spelled(1, 2, 3, 4)
    try expect_false(value.x_ != 1 or value.x != 2 or value.a_b != 3 or value.aB != 4)

    var clone = value.clone()
    clone.x_ = 9
    try expect_false(value.x_ != 1 or clone.x_ != 9)
    try expect_equal(value, Spelled(1, 2, 3, 4))

test "operation names that differ only in underscores stay distinct":
    let methods: Methods = Spelled(1, 2, 3, 4)
    try expect_false(methods.foo_bar() != 1 or methods.fooBar() != 2)

test "functions named like Go predeclared identifiers still lower":
    let text = f"{string(1)}{int(1)}{float64(1)}{nil(1)}"
    let floats = [1.5, 2.5]
    try expect_false(text != "2345" or floats.length() != 2)

type Box[T]:
    value: T

type Box_Int:
    value: String

type Shape:
    case Circle(radius: Int)
    case Square(side: Int)

type Shape_Circle:
    radius: String

def side(shape: Shape) -> Int:
    match shape:
        case Circle(radius): return radius
        case Square(side): return side

test "declared names stay apart from instantiation and case names":
    let boxed = Box[Int](1)
    let named = Box_Int("one")
    try expect_false(boxed.value != 1 or named.value != "one")
    try expect_false(side(Shape.Circle(3)) != 3 or side(Shape.Square(4)) != 4)
    try expect_equal(Shape_Circle("r").radius, "r")

interface Counter:
    def count() -> Int

type Tally:
    total: Int

impl Counter for Tally:
    def count() -> Int:
        return self.total

type Counter_Tally:
    other: Int

def clone_Tally(tally: Tally) -> Int:
    return tally.total + 1

test "view and helper names stay apart from declared names":
    let tally = Tally(1)
    let copy = tally.clone()
    let view: Counter = tally
    try expect_false(view.count() != 1 or Counter_Tally(2).other != 2)
    try expect_false(copy.total != 1 or clone_Tally(tally) != 2)

interface Reporter:
    def describe() -> String
    def receiver() -> String

impl Reporter for Tally:
    def describe() -> String:
        return f"describe {self.total}"

    def receiver() -> String:
        return f"receiver {self.total}"

test "operations named like generated view methods stay callable":
    let reporter: Reporter = Tally(3)
    try expect_false(
        (
            reporter.describe() != "describe 3"
            or reporter.receiver() != "receiver 3"
        )
    )
