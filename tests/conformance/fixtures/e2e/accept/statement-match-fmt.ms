# conform: tags=alternatives,control-flow,faults,formatter,lists,match,modules,mutation,optional,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/statement-match.ms
import {expect_equal} from "@std/testing.ms"

type Shape:
    case Circle(r: Int)
    case Rect(w: Int, h: Int)
    case Dot

fn area(shape: Shape) Int:
    match shape:
        Circle(r): return 3 * r * r
        Rect(w, h): return w * h
        Dot: return 0

    return -1

fn first_positive(values: List[Optional[Int]]) Int:
    var index = 0

    while index < values.length():
        let item = values.get(index)
        index += 1

        match item:
            none: continue
            some(value):
                if value > 0:
                    return value

    return -1

fn nested(rows: List[List[Optional[Int]]]) Int:
    var total = 0

    for row in rows:
        for item in row:
            match item:
                none: break
                some(value): total += value

        total += 1000

    return total

fn side_effects(shape: Shape) Int:
    var count = 0

    match shape:
        Circle(r):
            count += r
        _:
            count += 100

    return count

test "statement match returns from the enclosing function":
    try expect_equal(area(Shape.Circle(2)), 12)
    try expect_equal(area(Shape.Rect(3, 4)), 12)
    try expect_equal(area(Shape.Dot), 0)

test "statement match controls the nearest loop":
    let values: List[Optional[Int]] = [none, some(0), some(5), some(9)]
    try expect_equal(first_positive(values), 5)
    try expect_equal(first_positive([none, some(-1)]), -1)

    let rows: List[List[Optional[Int]]] = [
        [some(1), none, some(100)], [some(2), some(3)]
    ]
    try expect_equal(nested(rows), 2006)

test "statement match arms assign enclosing locals":
    try expect_equal(side_effects(Shape.Circle(7)), 7)
    try expect_equal(side_effects(Shape.Dot), 100)
