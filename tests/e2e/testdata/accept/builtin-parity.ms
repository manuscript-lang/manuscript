import (
	Bytes from "@std/bytes.ms",
	RangeOptions,
	filled,
	map_from_entries,
	range_by from "@std/collections/collections.ms",
	from_int from "@std/math/math.ms",
	compile from "@std/string.ms",
	expect_equal, expect_false, expect_true, fail from "@std/test/test.ms",
)

fn positive(value: Int) Bool:
	return value > 0

fn negative(value: Int) Bool:
	return value < 0

fn stringify(value: Int) String:
	return value.to_string_radix(radix: 10)

fn expand(value: Int) List[String]:
	return [stringify(value: value), "x"]

fn total(accumulator: Int, value: Int) Int:
	return accumulator + value

fn ordered(accumulator: String, value: Int) String:
	return "{accumulator}{value}"

fn compare(left: Int, right: Int) Int:
	if left < right: return -1
	if left > right: return 1

	return 0

fn common_result[T](result: T!) T!:
	match result:
		ok(value):
			return ok(value)
		error(cause):
			return error(cause)

fn checked_expansion() Unit!:
	(
		not (
			common_result(
				result: filled(value: "a", count: 3, max_items: 3)
			)? == ["a", "a", "a"]
		)
	) | expect_false?
	(
		not (
			common_result(
				result: range_by(
					start: 0, end: 6, step: 2, options: RangeOptions(max_items: 3)
				)
			)? == [0, 2, 4]
		)
	) | expect_false?
	(
		not (
			common_result(
				result: range_by(
					start: 3, end: -1, step: -1, options: RangeOptions(max_items: 4)
				)
			)? == [3, 2, 1, 0]
		)
	) | expect_false?
	"x".pad_start(target_length: 4, padding: "é🙂") | expect_equal("é🙂éx")?
	"x".pad_end(target_length: 4, padding: "é🙂") | expect_equal("xé🙂é")?
	(not ("aba".replace(old: "a", new: "é") == "ébé")) | expect_false?
	(not ("é🙂".replace(old: "", new: "-") == "-é-🙂-")) | expect_false?
	(common_result(result: "é🙂".slice_scalars(start: 0, end: 1))?) | expect_equal("é")?
	(common_result(result: "é".repeat(count: 3, max_bytes: 6))?) | expect_equal("ééé")?

test "list methods mutate explicit clones and remain typed":
	original := [3, 1, 2, 1]
	alias := original.clone()
	original.get(index: -1) | expect_equal(1)?

	absent: Int? := none
	original.get(index: -9223372036854775808, default: -1) | expect_equal(-1)?
	original.get(index: 9223372036854775807, default: -1) | expect_equal(-1)?
	original.first() | expect_equal(3)?
	original.last() | expect_equal(1)?

	empty: List[Int] := []
	empty.first() | expect_equal(absent)?
	empty.last() | expect_equal(absent)?
	(empty.is_empty()) | expect_true?
	(not original.is_empty()) | expect_true?
	(original.contains(value: 2)) | expect_true?
	(not original.contains(value: 8)) | expect_true?
	original.index_of(value: 1) | expect_equal(1)?
	original.last_index_of(value: 1) | expect_equal(3)?
	original.index_of(value: 8) | expect_equal(absent)?
	original.last_index_of(value: 8) | expect_equal(absent)?

	var chain_1 = original.clone()
	chain_1.prepend(value: 0)
	chain_1 | expect_equal([0, 3, 1, 2, 1])?

	var chain_2 = original.clone()
	chain_2.set(index: -1, value: 9)
	chain_2 | expect_equal([3, 1, 2, 9])?

	var chain_3 = original.clone()
	chain_3.remove(index: 1)
	chain_3 | expect_equal([3, 2, 1])?
	original.slice(start: 1, end: 3).get() | expect_equal([1, 2])?

	var chain_4 = original.clone()
	chain_4.reverse()
	chain_4 | expect_equal([1, 2, 1, 3])?
	original.sorted(compare: compare) | expect_equal([1, 1, 2, 3])?
	[-1, 0, 2, 3].filter(predicate: positive) | expect_equal([2, 3])?
	[-1, 0, 2, 3].find(predicate: positive) | expect_equal(2)?
	[-1, 0, 2, 3].find_last(predicate: positive) | expect_equal(3)?
	[-1, 0, 2, 3].find_index(predicate: positive) | expect_equal(2)?
	[-1, 0, 2, 3].find_last_index(predicate: positive) | expect_equal(3)?
	original.find(predicate: negative) | expect_equal(absent)?
	original.find_last(predicate: negative) | expect_equal(absent)?
	original.find_index(predicate: negative) | expect_equal(absent)?
	original.find_last_index(predicate: negative) | expect_equal(absent)?
	(original.any(predicate: positive)) | expect_true?
	(original.all(predicate: positive)) | expect_true?
	(not original.any(predicate: negative)) | expect_true?
	(not original.all(predicate: negative)) | expect_true?
	(not empty.any(predicate: positive)) | expect_true?
	(empty.all(predicate: positive)) | expect_true?

	var observed_original: List[Int] = []
	original.for_each(
		fn(value) Unit:
			observed_original.append(value)
	)
	observed_original | expect_equal(original)?
	original.map(transform: stringify) | expect_equal(["3", "1", "2", "1"])?
	expect_true(
		(
			original.map[String](transform: stringify).join(
				separator: ","
			) == "3,1,2,1"
		)
	)?
	(
		not (
			original.flat_map(transform: expand) == [
				"3", "x", "1", "x", "2", "x", "1", "x"
			]
		)
	) | expect_false?
	original.fold(initial: 0, step: total) | expect_equal(7)?
	original.fold_right(initial: "", step: ordered) | expect_equal("1213")?

	convert := original.map[String]
	convert(transform: stringify) | expect_equal(["3", "1", "2", "1"])?

	var reversing = original.clone()
	reverse := reversing.reverse
	reverse()
	reversing | expect_equal([1, 2, 1, 3])?

	reduce := original.fold[Int]
	reduce(initial: 0, step: total) | expect_equal(7)?

	var chain_5 = original.clone()
	chain_5.splice(start: 1, delete_count: 2, replacement: [8, 9, 10])
	(not (chain_5 == [3, 8, 9, 10, 1])) | expect_false?

	var chain_6 = original.clone()
	chain_6.fill(value: 0, start: 1, end: 3)
	(chain_6 | expect_equal([3, 0, 0, 1])?)

	var chain_7 = original.clone()
	chain_7.copy_within(target: 1, start: 0, end: 3)
	(chain_7 | expect_equal([3, 3, 1, 2])?)
	original.keys() | expect_equal([0, 1, 2, 3])?
	original.entries().get(index: 0) | expect_equal(ListEntry(index: 0, value: 3))?
	original.to_set().values() | expect_equal([3, 1, 2])?
	expect_equal(
		[[1, 2], [], [3]].flat_map(transform: fn value: value.clone()), [1, 2, 3]
	)?
	alias | expect_equal([3, 1, 2, 1])?

test "map enumeration, merge, and clear preserve insertion order":
	var original = Map[String, Int]()
	original.add(key: "a", value: 1)
	original.add(key: "b", value: 2)

	var other = Map[String, Int]()
	other.add(key: "b", value: 3)
	other.add(key: "c", value: 4)

	var merged = original.clone()
	merged.merge(other: other.clone())
	merged.keys() | expect_equal(["a", "b", "c"])?
	merged.values() | expect_equal([1, 3, 4])?
	(
		not (
			merged.entries() == [
				MapEntry(key: "a", value: 1), MapEntry(key: "b", value: 3),
				MapEntry(key: "c", value: 4)
			]
		)
	) | expect_false?
	map_from_entries(entries: merged.entries()) | expect_equal(merged)?
	(
		not (
			map_from_entries(
				entries: [
					MapEntry(key: "a", value: 1), MapEntry(key: "a", value: 2)
				]
			).values() == [2]
		)
	) | expect_false?

	var observed_keys: List[String] = []
	var observed_values: List[Int] = []

	merged.for_each(
		fn key,
		value:
			observed_keys.append(key.clone())
			observed_values.append(value)
	)

	observed_keys | expect_equal(merged.keys())?
	observed_values | expect_equal(merged.values())?

	get_keys := merged.keys
	get_keys() | expect_equal(["a", "b", "c"])?

	var chain_1 = original.clone()
	chain_1.clear()
	chain_1.length() | expect_equal(0)?
	original.values() | expect_equal([1, 2])?
	other.values() | expect_equal([3, 4])?

test "set algebra and enumeration preserve source values":
	left := [1, 2, 3].to_set()
	right := [3, 4].to_set()
	left.union(other: right).values() | expect_equal([1, 2, 3, 4])?
	left.intersection(other: right).values() | expect_equal([3])?
	left.difference(other: right).values() | expect_equal([1, 2])?
	left.symmetric_difference(other: right).values() | expect_equal([1, 2, 4])?
	([3].to_set().is_subset_of(other: left)) | expect_true?
	(left.is_superset_of(other: [1, 3].to_set())) | expect_true?
	(not left.is_subset_of(other: right)) | expect_true?
	(not right.is_superset_of(other: left)) | expect_true?
	(left.is_disjoint_from(other: [5].to_set())) | expect_true?
	(not left.is_disjoint_from(other: right)) | expect_true?

	empty := Set[Int]()
	(empty.is_subset_of(other: left)) | expect_true?
	(left.is_superset_of(other: empty)) | expect_true?
	(empty.is_disjoint_from(other: left)) | expect_true?

	var observed_left: List[Int] = []
	left.for_each(
		fn(value) Unit:
			observed_left.append(value)
	)
	observed_left | expect_equal(left.values())?

	var chain_8 = left.clone()
	chain_8.clear()
	chain_8 | expect_equal(empty)?
	left.values() | expect_equal([1, 2, 3])?

test "string methods use Unicode scalars":
	"é🙂é".get(index: -1) | expect_equal("é")?
	"é🙂é".scalar_at(index: 1) | expect_equal(128578)?

	_missing: String? := none
	"".get(index: 0, default: "?") | expect_equal("?")?
	"é".get(index: -9223372036854775808, default: "?") | expect_equal("?")?
	"é🙂é".index_of(value: "🙂") | expect_equal(1)?
	"é🙂é".last_index_of(value: "é") | expect_equal(2)?
	"é🙂é".last_index_of(value: "") | expect_equal(3)?
	"é🙂é".index_of(value: "") | expect_equal(0)?

	absent: Int? := none
	"é🙂é".index_of(value: "z") | expect_equal(absent)?
	"é🙂é".last_index_of(value: "z") | expect_equal(absent)?
	"é🙂é".slice(start: -2, end: 3).get() | expect_equal("🙂é")?
	("é🙂é".slice(start: 2, end: 1).is_error()) | expect_true?
	("é🙂é".slice(start: -99, end: 1).is_error()) | expect_true?
	"é🙂".scalar_length() | expect_equal(2)?
	"é🙂".scalar_values() | expect_equal([233, 128578])?
	"\t hello \n".trim() | expect_equal("hello")?
	"\t hello \n".trim_start() | expect_equal("hello \n")?
	"\t hello \n".trim_end() | expect_equal("\t hello")?
	"éAb".upper() | expect_equal("ÉAB")?
	"ÉAB".lower() | expect_equal("éab")?
	("abc".contains(value: "b")) | expect_true?
	("abc".starts_with(prefix: "ab")) | expect_true?
	("abc".ends_with(suffix: "bc")) | expect_true?
	"a,b,c".split(separator: ",", max_parts: 2) | expect_equal(["a", "b"])?
	"aba".replace_first(old: "a", new: "x") | expect_equal("xba")?

	strip := " hello ".trim
	strip() | expect_equal("hello")?

	match checked_expansion():
		ok(_):
			_completed := unit
		error(cause):
			return fail(message: cause.message)

test "bytes have analogous immutable operations":
	data := Bytes([1, 2, 3, 2])
	data.get(index: -1) | expect_equal(2)?

	missing: Int? := none
	data.get(index: -9223372036854775808, default: 255) | expect_equal(255)?
	(data.contains(value: Bytes([2, 3]))) | expect_true?
	data.index_of(value: Bytes([2])) | expect_equal(1)?
	data.last_index_of(value: Bytes([2])) | expect_equal(3)?
	data.index_of(value: Bytes([9])) | expect_equal(missing)?
	(data.starts_with(prefix: Bytes([1, 2]))) | expect_true?
	(data.ends_with(suffix: Bytes([3, 2]))) | expect_true?
	data.slice(start: 1, end: 3).get() | expect_equal(Bytes([2, 3]))?
	data.reversed() | expect_equal(Bytes([2, 3, 2, 1]))?
	data.with_value(index: -1, value: 255) | expect_equal(Bytes([1, 2, 3, 255]))?
	(Bytes([]).is_empty()) | expect_true?
	(not data.is_empty()) | expect_true?
	data | expect_equal(Bytes([1, 2, 3, 2]))?
	255.to_string_radix(radix: 16) | expect_equal("ff")?
	1.5.to_string() | expect_equal("1.5")?
	(1.5.is_finite()) | expect_true?
	(not 1.5.is_nan()) | expect_true?

test "growth limits and invalid inputs return values":
	"abc".pad_start(target_length: 1, padding: "") | expect_equal("abc")?
	"x".pad_start(target_length: -1, padding: " ") | expect_equal("x")?
	"x".pad_end(target_length: 4, padding: "") | expect_equal("x")?

	list_limit: List[Int]! := error(
		Error("collection: limit exceeded", kind: "EOVERFLOW")
	)
	list_invalid: List[Int]! := error(
		Error("collection: invalid input", kind: "EINVAL")
	)
	range_by(start: 0, end: 4, step: 1, options: RangeOptions(max_items: 3)) | expect_equal(
		list_limit
	)?
	range_by(start: 0, end: 4, step: 0, options: RangeOptions(max_items: 3)) | expect_equal(
		list_invalid
	)?
	filled(value: 1, count: 2, max_items: 1) | expect_equal(list_limit)?

fn parity(value: Int) Int:
	return value % 2

fn default_value(key: String) Int:
	if key != "c": return -1
	return 3

test "grouping and lazy map defaults":
	grouped := [1, 2, 3, 4].group_by(key: parity)
	grouped.keys() | expect_equal([1, 0])?
	grouped.values() | expect_equal([[1, 3], [2, 4]])?

	group := [1, 2, 3, 4].group_by[Int]
	group(key: parity) | expect_equal(grouped)?

	var original = Map[String, Int]()
	original.add(key: "a", value: 1)
	original.add_default(key: "a", value: 9)
	original | expect_equal(original)?

	var calls: List[Int] = []

	create := fn(key: String):
		calls.append(1)
		return 0

	original.add_default_from(key: "a", create: create)
	original | expect_equal(original)?

	var chain_9 = original.clone()
	chain_9.add_default(key: "b", value: 2)
	chain_9.values() | expect_equal([1, 2])?

	var chain_10 = original.clone()
	chain_10.add_default_from(key: "c", create: default_value)
	(not (chain_10.values() == [1, 3])) | expect_false?
	original.values() | expect_equal([1])?
	calls.length() | expect_equal(0)?

fn verify_text_and_numbers() Unit!:
	(common_result(result: "é".normalize(form: "NFC", max_bytes: 2))?) | expect_equal(
		"é"
	)?
	(common_result(result: "é".normalize(form: "NFD", max_bytes: 3))?) | expect_equal(
		"é"
	)?
	expect_true(
		(
			common_result(
				result: "ﬁ".normalize(form: "NFKC", max_bytes: 2)
			)? == "fi"
		)
	)?
	expect_true(
		(
			common_result(
				result: "ﬁ".normalize(form: "NFKD", max_bytes: 2)
			)? == "fi"
		)
	)?
	1.5.to_fixed(digits: 3) | expect_equal("1.500")?
	1.5.to_exponential(digits: 3) | expect_equal("1.500e+0")?
	1.5.to_precision(precision: 4) | expect_equal("1.500")?
	12345.0.to_precision(precision: 3) | expect_equal("1.23e+4")?
	0.000001.to_precision(precision: 2) | expect_equal("0.0000010")?

test "normalization, empty separators, and precision formatting":
	match verify_text_and_numbers():
		ok(_):
			_completed := unit
		error(cause):
			return fail(message: cause.message)

	"é🙂".split(separator: "", max_parts: 8) | expect_equal(["é", "🙂"])?

	empty_texts: List[String] := []
	"".split(separator: "", max_parts: 8) | expect_equal(empty_texts)?
	"é🙂".replace_first(old: "", new: "-") | expect_equal("-é🙂")?
	"".replace_first(old: "", new: "-") | expect_equal("-")?
	"é".concat(other: "🙂") | expect_equal("é🙂")?

	invalid: String! := error(Error("string: invalid input", kind: "EINVAL"))
	limit: String! := error(Error("string: limit exceeded", kind: "EOVERFLOW"))
	"é".normalize(form: "invalid", max_bytes: 8) | expect_equal(invalid)?
	"é".normalize(form: "NFD", max_bytes: 2) | expect_equal(limit)?

fn verify_bigint_and_regex() Unit!:
	a := from_int(value: 12)
	b := from_int(value: 5)
	a.add(other: b).to_string_radix(radix: 10) | expect_equal("17")?
	a.subtract(other: b).to_string_radix(radix: 10) | expect_equal("7")?
	a.multiply(other: b).to_string_radix(radix: 10) | expect_equal("60")?
	(common_result(result: a.divide(other: b))?).to_int() | expect_equal(2)?
	(common_result(result: a.remainder(other: b))?).to_int() | expect_equal(2)?
	a.compare(other: b) | expect_equal(1)?
	a.bit_and(other: b).to_int() | expect_equal(4)?
	a.bit_or(other: b).to_int() | expect_equal(13)?
	a.bit_xor(other: b).to_int() | expect_equal(9)?

	// A Regex has one owner and no clone, so the lent part comes from a binding, not a temporary.
	compiled := compile(pattern: "[0-9]+")
	pattern := common_result(result: compiled)?
	(pattern.matches(text: "a12b3")) | expect_true?
	(
		not (
			common_result(
				result: pattern.find_all(text: "a12b3", max_matches: 2)
			)? == ["12", "3"]
		)
	) | expect_false?
	(
		not (
			common_result(
				result: pattern.replace_all(
					text: "a12b3", replacement: "x", max_bytes: 4
				)
			)? == "axbx"
		)
	) | expect_false?

test "BigInt and Regex share function implementations with methods":
	match verify_bigint_and_regex():
		ok(_):
			_completed := unit
		error(cause):
			return fail(message: cause.message)

test "generic native methods accept omitted single-parameter labels":
	values := [1, 2]
	values.map(stringify) | expect_equal(["1", "2"])?
	values.map[String](stringify) | expect_equal(["1", "2"])?
	values.flat_map(expand) | expect_equal(["1", "x", "2", "x"])?
	values.group_by(parity).keys() | expect_equal([1, 0])?

	convert := values.map[String]
	convert(stringify) | expect_equal(["1", "2"])?

	var observed_values: List[Int] = []
	values.for_each(
		fn(value) Unit:
			observed_values.append(value)
	)
	observed_values | expect_equal(values)?
