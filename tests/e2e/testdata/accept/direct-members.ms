import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

type Point:
    x: Int
    y: Int

impl Equal for Point:
    fn equals(other: Equal) -> Bool:
        match other:
            Point(value): return self.x == value.x
            _: return false

fn contains_generic[T: Equal](values: List[T], value: T) -> Bool:
    return values.contains(value)

test "list members match generic dispatch":
    let values: List[Int] = []
    values.append(1)
    values.append(2)
    values.is_empty() | try expect_false
    (values.contains(2)) | try expect_true
    values.contains(3) | try expect_false
    let points: List[Point] = [Point(x: 1, y: 2)]
    (points.contains(Point(x: 1, y: 2))) | try expect_true
    (contains_generic(values: points, value: Point(x: 1, y: 2))) | try expect_true

test "map and set members":
    let m: Map[String, Int] = {}
    let updated = m.add("a", 1).add("a", 2).add("b", 3)
    updated.get("a").unwrap() | try expect_equal(expected: 2)
    updated.get("z").is_some() | try expect_false
    (updated.contains("b")) | try expect_true
    let s: Set[Int] = Set()
    let grown = s.add(1).add(1).add(2)
    grown.length() | try expect_equal(expected: 2)
    (grown.contains(2)) | try expect_true

test "string at":
    let text = "héllo"
    text.at(1).unwrap() | try expect_equal(expected: "é")
    text.at(10).is_some() | try expect_false
