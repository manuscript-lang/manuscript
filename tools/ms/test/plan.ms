// Which tests a run covers and in what order: the selection options, the seeded
// shuffle, and the file number the harness gives each test.
import (
	bit_and,
	bit_xor,
	shift_right_unsigned,
	wrapping_add,
	wrapping_multiply from "@std/math/math.ms",
	compile from "@std/regex.ms",
	expect_equal from "@std/test/test.ms",

	TestOptions from "./options.ms",
)

// The selection a run makes: positions in the listing, in execution order, or the first
// name that is not a test.
export type Selection:
	indices: List[Int] = []
	unknown: String = ""

fn mix(state: Int) Int:
	var z = state
	z = wrapping_multiply(bit_xor(z, shift_right_unsigned(z, 30)), -4658895280553007687)
	z = wrapping_multiply(bit_xor(z, shift_right_unsigned(z, 27)), -7723592293110705685)
	return bit_xor(z, shift_right_unsigned(z, 31))

// `value` modulo `size`, for `value` read as an unsigned 64-bit number.
fn unsigned_mod(value: Int, size: Int) Int:
	half := shift_right_unsigned(value, 1)
	return ((half % size) * 2 + bit_and(value, 1)) % size

// A seeded Fisher-Yates permutation of `items`.
export fn shuffled(items: List[Int], seed: Int) List[Int]:
	var out = items.clone()
	var state = bit_xor(seed, -7046029254386353131)
	var at = out.length() - 1

	while at >= 1:
		state = wrapping_add(state, -7046029254386353131)

		pick := unsigned_mod(mix(state), at + 1)
		held := out[at]
		out[at] = out[pick]
		out[pick] = held
		at -= 1

	return out

// The tests of `available` that `options` select, in listing order.
export fn select(available: List[String], options: TestOptions) Selection:
	var found = List[Bool]()
	for name in options.names: found.append(false)

	matching := compile(options.matching).get()
	exclude := compile(options.exclude).get()
	var out = Selection()

	for index in 0..available.length():
		name := available[index]
		var exact = options.names.is_empty()

		for at in 0..options.names.length():
			if options.names[at] == name:
				exact = true
				found[at] = true

		if (
			exact
			and name.contains(options.filter)
			and matching.matches(name)
			and (options.exclude.is_empty() or not exclude.matches(name))
		):
			out.indices.append(index)

	for at in 0..found.length():
		if not found[at]:
			out.unknown = options.names[at].clone()
			break

	return out

// The harness's file number of each test: files are numbered in the order of their
// first test, and a test is named `file::test`.
export fn file_numbers(names: List[String]) List[Int]:
	var seen = List[String]()
	var out = List[Int]()

	for name in names:
		var file = name.clone()
		if pair := name.split_once("::"): file = pair.before.clone()

		var at = -1
		for known in 0..seen.length():
			if seen[known] == file: at = known

		if at < 0:
			seen.append(file)
			at = seen.length() - 1

		out.append(at)

	return out

test "files are numbered by first appearance":
	numbers := file_numbers(["a.ms::x", "b.ms::y", "a.ms::z"])
	expect_equal(numbers, [0, 1, 0])?

test "a shuffle is a permutation and the same for a seed":
	items := [0, 1, 2, 3, 4, 5, 6, 7]
	once := shuffled(items, 42)
	expect_equal(once, shuffled(items, 42))?
	expect_equal(once.sorted(), items)?
