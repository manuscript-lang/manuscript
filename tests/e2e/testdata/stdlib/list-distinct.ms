import expect_equal from "@std/test/test.ms"

fn unique_copy[T: Equal & Clonable](values: List[T]) List[T]:
	copy_unique := values.distinct
	return copy_unique()

test "generic distinct method values copy nested elements independently":
	source := [[1], [1], [2]]
	var result = unique_copy(source)
	result[0].append(3)
	try expect_equal(result, [[1, 3], [2]])
	try expect_equal(source, [[1], [1], [2]])

type Key:
	id: Int
	payload: List[Int]

impl Equal for Key:
	fn equals(other: Key) Bool:
		return self.id == other.id

impl Hashable for Key:
	fn hash() Int:
		return 0

test "hash collisions keep the first representative and copy nested payloads":
	var source: List[Key] = []
	for i in 0..40:
		source.append(Key(i % 4, [i]))

	var result = source.distinct()
	try expect_equal(result.length(), 4)

	for i in 0..4:
		try expect_equal(result[i].id, i)
		try expect_equal(result[i].payload, [i])

	result[0].payload.append(99)
	try expect_equal(source[0].payload, [0])
	try expect_equal(result[0].payload, [0, 99])

test "distinct keeps first-seen order above the hashing threshold":
	var source: List[Int] = []
	for i in 0..64:
		source.append(31 - i % 32)

	result := source.distinct()
	try expect_equal(result, (0..32).reversed())
	try expect_equal(source.length(), 64)
	try expect_equal(source[32], 31)

test "set algebra preserves collision order and first representatives":
	left := Set([Key(2, [20]), Key(0, [0]), Key(1, [10]), Key(2, [99])])
	right := Set([Key(1, [999]), Key(3, [30])])
	intersection := left.intersection(right).values()
	try expect_equal(intersection.length(), 1)
	try expect_equal(intersection[0].payload, [10])

	difference := left.difference(right).values()
	try expect_equal(difference.map(fn(k: Key) Int: k.id), [2, 0])
	try expect_equal(difference[0].payload, [20])

	symmetric := left.symmetric_difference(right).values()
	try expect_equal(symmetric.map(fn(k: Key) Int: k.id), [2, 0, 3])
	try expect_equal(symmetric[0].payload, [20])
	try expect_equal(symmetric[2].payload, [30])
	try expect_equal(left.values()[0].payload, [20])
	try expect_equal(right.values()[0].payload, [999])

test "distinct copies nested values into independent output storage":
	var source: List[List[Int]] = []
	for i in 0..32:
		source.append([i % 4])

	var result = source.distinct()
	try expect_equal(result, [[0], [1], [2], [3]])
	result[0].append(99)
	try expect_equal(source[0], [0])
	try expect_equal(result[0], [0, 99])

test "distinct preserves owned strings, empty and small lists":
	empty: List[String] := []
	try expect_equal(empty.distinct(), [])
	try expect_equal(["b", "a", "b"].distinct(), ["b", "a"])

	var source: List[String] = []
	for i in 0..40:
		source.append("heap-backed-distinct-key-{i % 3}")
	try expect_equal(
		source.distinct(),
		[
			"heap-backed-distinct-key-0", "heap-backed-distinct-key-1",
			"heap-backed-distinct-key-2"
		]
	)
	try expect_equal(source.length(), 40)
