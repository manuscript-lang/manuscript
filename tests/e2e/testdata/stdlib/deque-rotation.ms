import (
	Deque from "@std/collections/deque.ms",
	expect_equal from "@std/test/test.ms",
)

test "rotation preserves order across ring positions and signed boundaries":
	for size in [0, 1, 2, 3, 4, 7, 8, 9, 17]:
		for advance in [0, 1, 5]:
			for count in [
				-9223372036854775808, -100, -size - 1, -size, -size + 1,
				-(size / 2) - 1, -(size / 2), -(size / 2) + 1, -1, 0, 1, size / 2,
				size / 2 + 1, size - 1, size, size + 1, 100, 9223372036854775807
			]:
				var q = Deque[Int]()
				for i in 0..size:
					q.push_back(i)
				for i in 0..advance:
					if value := q.pop_front():
						q.push_back(value)
				q.rotate(count)
				try expect_equal(q.length(), size)

				if size > 0:
					shift := (count % size + size + advance % size) % size
					for i in 0..size:
						try expect_equal(q.at(i).get(-1), (i + shift) % size)
					try expect_equal(q.front(), q.at(0))
					try expect_equal(q.back(), q.at(size - 1))

test "negative rotation keeps optional values and nested contents":
	var q = Deque[List[Int]?]()
	q.push_back([1, 2])
	q.push_back(none)
	q.push_back([3])
	q.rotate(-1)

	last: List[Int]? = [3]
	first: List[Int]? = [1, 2]
	absent: List[Int]? = none
	try expect_equal(q.pop_front(), last)
	try expect_equal(q.pop_front(), first)
	try expect_equal(q.pop_front(), absent)
	try expect_equal(q.pop_front(), none)

test "positive near-whole rotations preserve full and partial rings":
	for size in [8191, 8192]:
		var q = Deque[Int]()
		for i in 0..size:
			q.push_back(i)
		for unused in 0..100:
			q.rotate(size - 1)
		try expect_equal(q.length(), size)
		for i in 0..size:
			try expect_equal(q.at(i).get(-1), (i + size - 100) % size)
		q.push_back(size)
		try expect_equal(q.pop_back(), size)
		q.rotate(100)
		for i in 0..size:
			try expect_equal(q.pop_front(), i)
		try expect_equal(q.is_empty(), true)

test "positive near-whole rotation preserves optional nested payloads":
	var q = Deque[List[Int]?]()
	q.push_back([1, 2])
	q.push_back(none)
	q.push_back([3])
	q.rotate(2)

	last: List[Int]? = [3]
	first: List[Int]? = [1, 2]
	absent: List[Int]? = none
	try expect_equal(q.pop_front(), last)
	try expect_equal(q.pop_front(), first)
	try expect_equal(q.pop_front(), absent)
	try expect_equal(q.is_empty(), true)
