import {expect_equal} from "@std/testing.ms"

type Shape:
    case Circle(r: Int)
    case Rect(w: Int, h: Int)
    case Dot

fn area(shape: Shape) -> Int:
    match shape:
        Circle(r): return 3 * r * r
        Rect(w, h): return w * h
        Dot: return 0

    return -1

fn first_positive(values: List[Optional[Int]]) -> Int:
    var index = 0

    while index < values.length():
        let item = values.at(index).unwrap()
        index = index + 1

        match item:
            none: continue
            some(value):
                if value > 0:
                    return value

    return -1

fn nested(rows: List[List[Optional[Int]]]) -> Int:
    var total = 0

    for row in rows:
        for item in row:
            match item:
                none: break
                some(value): total = total + value

        total = total + 1000

    return total

fn side_effects(shape: Shape) -> Int:
    var count = 0

    match shape:
        Circle(r):
            count = count + r
        _:
            count = count + 100

    return count

test "statement match returns from the enclosing function":
    area(shape: Shape.Circle(r: 2)) | try expect_equal(expected: 12)
    area(shape: Shape.Rect(w: 3, h: 4)) | try expect_equal(expected: 12)
    area(shape: Shape.Dot) | try expect_equal(expected: 0)

test "statement match controls the nearest loop":
    let values: List[Optional[Int]] = [none, some(0), some(5), some(9)]
    first_positive(values: values) | try expect_equal(expected: 5)
    first_positive(values: [none, some(-1)]) | try expect_equal(expected: -1)
    let rows: List[List[Optional[Int]]] = [
        [some(1), none, some(100)],
        [some(2), some(3)]
    ]
    nested(rows: rows) | try expect_equal(expected: 2006)

test "statement match arms assign enclosing locals":
    side_effects(shape: Shape.Circle(r: 7)) | try expect_equal(expected: 7)
    side_effects(shape: Shape.Dot) | try expect_equal(expected: 100)
