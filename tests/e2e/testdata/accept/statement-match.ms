import panic from "@std/faults.ms"

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
        let item = values.at(index).unwrap()
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
    if not (area(Shape.Circle(2)) == 12):
        return panic("circle")
    if not (area(Shape.Rect(3, 4)) == 12):
        return panic("rect")
    if not (area(Shape.Dot) == 0):
        return panic("dot")

test "statement match controls the nearest loop":
    let values: List[Optional[Int]] = [none, some(0), some(5), some(9)]
    if not (first_positive(values) == 5):
        return panic("first positive")
    if not (first_positive([none, some(-1)]) == -1):
        return panic("no positive")

    let rows: List[List[Optional[Int]]] = [
        [some(1), none, some(100)],
        [some(2), some(3)]
    ]
    if not (nested(rows) == 2006):
        return panic("nested")

test "statement match arms assign enclosing locals":
    if not (side_effects(Shape.Circle(7)) == 7):
        return panic("bound arm")
    if not (side_effects(Shape.Dot) == 100):
        return panic("default arm")
