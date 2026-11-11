import expect_equal, expect_false, expect_true from "@std/test/test.ms"

type Visits:
	count: Int

fn mutate[T: Clonable](var values: List[T], mode: String, fill: List[T]) Unit:
	if mode == "remove":
		values.remove(0)
	if mode == "splice":
		values.splice(start: 1, delete_count: 2, replacement: fill.clone())
	if mode == "clear" or mode == "clear_append":
		values.splice(start: 0, delete_count: values.length(), replacement: [])

	if mode == "clear_append":
		values.splice(start: 0, delete_count: 0, replacement: fill.clone())
		values.splice(start: 0, delete_count: 0, replacement: fill)

fn step[T: Clonable](
	var seen: List[T], var visits: Visits, var values: List[T], value: T, mode: String,
	fill: List[T]
) Unit:
	seen.append(value)
	if visits.count == 0:
		mutate(values: var values, mode: mode, fill: fill)
	visits.count += 1

fn observe[T: Clonable](
	var values: List[T], mode: String, fill: List[T], callback: Bool
) List[T]!:
	var seen: List[T] = []
	var visits = Visits(0)

	if callback:
		(
			values
			.clone()
			.for_each(
				fn(value: T): step(
					var seen, var visits, var values, value.clone(), mode, fill.clone()
				)
			)
		)
	else:
		for value in values.clone():
			step(var seen, var visits, var values, value, mode, fill.clone())

	visits.count | expect_equal(3)?
	return ok(seen)

fn remaining[T: Clonable](mode: String, items: List[T], fill: List[T]) List[T]:
	var out = items
	if mode == "remove": out.remove(0)
	if mode == "splice": out.splice(
		start: 1, delete_count: 2, replacement: fill.clone()
	)
	if mode == "clear" or mode == "clear_append": out.splice(
		start: 0, delete_count: 3, replacement: []
	)

	if mode == "clear_append":
		out.splice(start: 0, delete_count: 0, replacement: fill.clone())
		out.splice(start: 0, delete_count: 0, replacement: fill)

	return out

test "Int consumers see the full snapshot while the live list shrinks":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var values = [1, 2, 3]
			clone := values.clone()
			want := remaining(mode, values.clone(), [9])
			seen := (observe(var values, mode, [9], callback)?)
			var total = 0
			var wanted = 0
			for value in seen: total += value
			for value in clone: wanted += value
			(
				not (
					total == wanted
					and seen == clone
					and values == want
					and clone == [1, 2, 3]
				)
			) | expect_false?

test "Float consumers see the full snapshot while the live list shrinks":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var values = [1.5, 2.5, 3.5]
			clone := values.clone()
			want := remaining(mode, values.clone(), [9.5])
			seen := (observe(var values, mode, [9.5], callback)?)
			var total = 0.0
			var wanted = 0.0
			for value in seen: total += value
			for value in clone: wanted += value
			(
				not (
					total == wanted
					and seen == clone
					and values == want
					and clone == [1.5, 2.5, 3.5]
				)
			) | expect_false?

test "String consumers see the full snapshot while the live list shrinks":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var values = ["a", "bb", "ccc"]
			clone := values.clone()
			want := remaining(mode, values.clone(), ["replacement"])
			seen := (observe(var values, mode, ["replacement"], callback)?)
			var text = ""
			for value in seen: text += value
			(
				not (
					text == clone.join("")
					and seen == clone
					and values == want
					and clone == ["a", "bb", "ccc"]
				)
			) | expect_false?

type Payload:
	value: Int

test "record consumers keep independent copies after shrink":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var last = Payload(3)
			var values = [Payload(1), Payload(2), last.clone()]
			clone := values.clone()
			want := remaining(mode, values.clone(), [Payload(9)])
			seen := (observe(var values, mode, [Payload(9)], callback)?)
			var total = 0
			var wanted = 0
			for value in seen: total += value.value
			for value in clone: wanted += value.value
			(not (total == wanted and seen == clone and values == want)) | expect_false?
			last.value = 11
			(not (seen.last().get().value == 3 and clone.last().get().value == 3)) | expect_false?

enum Choice:
	number(value: Int)
	label(value: String)

fn score(value: Choice) Int:
	match value:
		number(count): return count
		label(text): return text.length()

test "alternative consumers retain tags and payloads after shrink":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			first: Choice := number(1)
			second: Choice := label("bb")
			last: Choice := number(3)
			fill: List[Choice] := [label("replacement")]
			var values = [first.clone(), second.clone(), last.clone()]
			want := remaining(mode, values.clone(), fill.clone())
			seen := (observe(var values, mode, fill, callback)?)
			snapshot := [first, second, last]
			var total = 0
			var wanted = 0
			for value in seen: total += score(value.clone())
			for value in snapshot.clone(): wanted += score(value)
			(not (total == wanted and seen == snapshot and values == want)) | expect_false?

test "nested list consumers keep independent inner lists after shrink":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var last = [3]
			var values = [[1], [2], last.clone()]
			clone := values.clone()
			want := remaining(mode, values.clone(), [[9]])
			seen := (observe(var values, mode, [[9]], callback)?)
			var total = 0
			var wanted = 0
			for value in seen: total += value.first().get()
			for value in clone: wanted += value.first().get()
			(not (total == wanted and seen == clone and values == want)) | expect_false?
			last.append(11)
			expect_true((seen.last().get() == [3] and clone.last().get() == [3]))?

test "map and folds consume snapshots of the live list":
	var mapped = [1, 2, 3]
	var visits = Visits(0)

	output := (
		mapped
		.clone()
		.map(
			fn value:
				if visits.count == 0: mapped.remove(0)
				visits.count += 1
				return value + 10
		)
	)

	(output == [11, 12, 13] and mapped == [2, 3]) | expect_true?

	var folded = [1, 2, 3]
	visits.count = 0

	total := (
		folded
		.clone()
		.fold(
			0,
			fn accumulator,
			value:
				if visits.count == 0: folded.splice(
					start: 0, delete_count: 3, replacement: []
				)
				visits.count += 1
				return accumulator + value
		)
	)

	(total == 6 and folded.is_empty() and visits.count == 3) | expect_true?

	var reversed = [1, 2, 3]
	visits.count = 0

	backwards := (
		reversed
		.clone()
		.fold_right(
			0,
			fn accumulator,
			value:
				if visits.count == 0: reversed.remove(0)
				visits.count += 1
				return accumulator * 10 + value
		)
	)

	(backwards == 321 and reversed == [2, 3] and visits.count == 3) | expect_true?

interface ReadValue:
	fn read() Int

impl ReadValue for Payload:
	fn read() Int: self.value

test "interface view consumers dispatch after shrink":
	for callback in [false, true]:
		for mode in ["remove", "splice", "clear", "clear_append"]:
			var last_record = Payload(3)
			var values = [Payload(1), Payload(2), last_record.clone()]
			clone := values.clone()
			want := remaining(mode, values.clone(), [Payload(9)])
			seen := (observe(var values, mode, [Payload(9)], callback)?)
			var total = 0
			var wanted = 0
			for value in seen: total += value.read()
			for value in clone.clone(): wanted += value.read()
			(not (total == wanted and values.length() == want.length())) | expect_false?
			last_record.value = 11
			(not (seen.last().get().read() == 3 and clone.last().get().read() == 3)) | expect_false?

test "find returns the value passed to a mutating predicate":
	var forward = [1, 2, 3]

	found := forward.clone().find(
		fn value:
			forward.remove(0)
			return value == 1
	)

	(found.get() == 1 and forward == [2, 3]) | expect_true?

	var replaced = [1, 2, 3]

	original := (
		replaced
		.clone()
		.find(
			fn value:
				replaced.set(0, 9)
				return value == 1
		)
	)

	(original.get() == 1 and replaced == [9, 2, 3]) | expect_true?

	var reverse = [1, 2, 3]

	last := (
		reverse
		.clone()
		.find_last(
			fn value:
				if value == 2: reverse.remove(1)
				return value == 2
		)
	)

	(last.get() == 2 and reverse == [1, 3]) | expect_true?

	var last_replaced = [1, 2, 3]

	before := (
		last_replaced
		.clone()
		.find_last(
			fn value:
				last_replaced.set(2, 9)
				return value == 3
		)
	)

	(before.get() == 3 and last_replaced == [1, 2, 9]) | expect_true?

	var indexes = [1, 2, 3]

	index := (
		indexes
		.clone()
		.find_index(
			fn value:
				indexes.remove(0)
				return value == 1
		)
	)

	var reverse_indexes = [1, 2, 3]

	last_index := (
		reverse_indexes
		.clone()
		.find_last_index(
			fn value:
				if value == 2: reverse_indexes.remove(1)
				return value == 2
		)
	)

	(index.get() == 0 and last_index.get() == 1) | expect_true?

	record := Payload(1)
	var records = [record.clone(), Payload(2)]
	retained := (
		records
		.clone()
		.find(
			fn value:
				matches := value.value == 1
				records.set(0, Payload(9))
				return matches
		)
		.get()
	)
	(
		not (
			retained.value == 1
			and record.value == 1
			and records.first().get().value == 9
		)
	) | expect_false?

test "preferred List mutators and explicit reversed copy iterate snapshots":
	var values = [1, 2, 3]
	clone := values.clone()
	var seen: List[Int] = []

	for value in values.clone():
		seen.append(value)

		if seen.length() == 1:
			values.set(index: 1, value: 9)
			values.remove(index: 0)

	(seen == [1, 2, 3] and values == [9, 3] and clone == [1, 2, 3]) | expect_true?
	values.reverse()
	values.append(4)
	values | expect_equal([3, 9, 4])?

	separate := values.reversed()
	values.set(1, 5)
	(separate == [4, 9, 3] and values == [3, 5, 4]) | expect_true?

	var child = Payload(1)
	var children = [child.clone(), Payload(2)]
	shallow := children.reversed()
	child.value = 7
	children.remove(0)
	(shallow.last().get().value == 1 and children.length() == 1) | expect_true?
