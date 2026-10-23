import {expect_equal} from "@std/testing.ms"

type Point:
    x: Int
    y: Int

fn origin() Point:
    return Point(x: 1, y: 2)

test "var destructuring binds reassignable copies":
    var xs = [1, 2]
    var [a, b] = xs
    a += 10
    b = 7

    var point = origin()
    var {x, y} = point
    x += 5
    y = 0

    var [q, r] = [3, 4]
    q += r
    try expect_equal(xs, [1, 2])
    try expect_equal([a, b, x, y, q], [11, 7, 6, 0, 7])
    try expect_equal([point.x, point.y], [1, 2])
