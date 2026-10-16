import panic from "@std/faults.ms"

type Spelled:
    x_: Int
    x: Int
    a_b: Int
    aB: Int

interface Methods:
    fn foo_bar() -> Int
    fn fooBar() -> Int

impl Methods for Spelled:
    fn foo_bar() -> Int:
        return self.x_

    fn fooBar() -> Int:
        return self.x

fn string(value: Int) -> Int:
    return value + 1

fn int(value: Int) -> Int:
    return value + 2

fn float64(value: Int) -> Int:
    return value + 3

fn nil(value: Int) -> Int:
    return value + 4

test "field names that differ only in underscores stay distinct":
    let value = Spelled(x_: 1, x: 2, a_b: 3, aB: 4)
    if value.x_ != 1 or value.x != 2 or value.a_b != 3 or value.aB != 4: return panic(
        "fields"
    )

    let clone = value.clone()
    clone.x_ = 9
    if value.x_ != 1 or clone.x_ != 9: return panic("clone")
    if value != Spelled(x_: 1, x: 2, a_b: 3, aB: 4): return panic("equality")

test "operation names that differ only in underscores stay distinct":
    let methods = Methods(value: Spelled(x_: 1, x: 2, a_b: 3, aB: 4))
    if methods.foo_bar() != 1 or methods.fooBar() != 2: return panic("operations")

test "functions named like Go predeclared identifiers still lower":
    let text = "{string(1)}{int(1)}{float64(1)}{nil(1)}"
    let floats = [1.5, 2.5]
    if text != "2345" or floats.length != 2: return panic("predeclared names")

type Box[T]:
    value: T

type Box_Int:
    value: String

type Shape:
    case Circle(radius: Int)
    case Square(side: Int)

type Shape_Circle:
    radius: String

fn side(shape: Shape) -> Int:
    match shape:
        Circle(radius): return radius
        Square(side): return side

test "declared names stay apart from instantiation and case names":
    let boxed = Box[Int](value: 1)
    let named = Box_Int(value: "one")
    if boxed.value != 1 or named.value != "one": return panic("instantiation")
    if side(Shape.Circle(3)) != 3 or side(Shape.Square(4)) != 4: return panic("cases")
    if Shape_Circle(radius: "r").radius != "r": return panic("declared case-like name")

interface Counter:
    fn count() -> Int

type Tally:
    total: Int

impl Counter for Tally:
    fn count() -> Int:
        return self.total

type Counter_Tally:
    other: Int

fn clone_Tally(tally: Tally) -> Int:
    return tally.total + 1

test "view and helper names stay apart from declared names":
    let tally = Tally(total: 1)
    let copy = tally.clone()
    let view = Counter(value: tally)
    if view.count() != 1 or Counter_Tally(other: 2).other != 2: return panic("view")
    if copy.total != 1 or clone_Tally(tally) != 2: return panic("helper")

interface Reporter:
    fn describe() -> String
    fn receiver() -> String

impl Reporter for Tally:
    fn describe() -> String:
        return "describe {self.total}"

    fn receiver() -> String:
        return "receiver {self.total}"

test "operations named like generated view methods stay callable":
    let reporter = Reporter(value: Tally(total: 3))
    if reporter.describe() != "describe 3" or reporter.receiver() != "receiver 3": return panic(
        "view methods"
    )
