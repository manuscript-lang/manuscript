import expect_equal, expect_false from "@std/test/test.ms"

type Point:
	x: Int
	y: Int

impl Equal for Point:
	fn equals(other: Point) Bool:
		return self.x == other.x

fn contains_generic[T: Equal](values: List[T], value: T) Bool:
	return values.contains(value)

test "list members match generic dispatch":
	var values: List[Int] = []
	values.append(1)
	values.append(2)
	expect_false(values.is_empty())?
	expect_false(not values.contains(2))?
	expect_false(values.contains(3))?

	points: List[Point] := [Point(1, 2)]
	expect_false(not points.contains(Point(1, 2)))?
	expect_false(not contains_generic(points, Point(1, 2)))?

test "map and set members":
	var m: Map[String, Int] = {}
	m.add("a", 1)
	m.add("a", 2)
	m.add("b", 3)

	updated := m
	expect_equal(updated["a"], 2)?
	expect_false(updated.get("z").is_some())?
	expect_false(not updated.contains("b"))?

	var s: Set[Int] = Set()
	s.add(1)
	s.add(1)
	s.add(2)

	grown := s
	expect_equal(grown.length(), 2)?
	expect_false(not grown.contains(2))?

test "string at":
	text := "héllo"
	expect_equal(text.get(1), "é")?
	expect_equal(text.get(10, default: ""), "")?
